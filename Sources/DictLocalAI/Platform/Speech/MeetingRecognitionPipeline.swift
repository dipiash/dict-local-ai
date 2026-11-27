import DictCore
import FluidAudio
import Foundation
import Synchronization

final class MeetingRecognitionPipeline: Sendable {
  private struct State: Sendable {
    var buffer = MeetingAudioBuffer()
    var scheduled = false
    var finishing = false
    var failure: Error?
    var waiters: [CheckedContinuation<Void, Never>] = []
    var completion: (@MainActor @Sendable (Result<Void, Error>) -> Void)?
  }
  private struct StoredWindow {
    let tokens: [RecognizedToken]
    let start: Double
    let end: Double
  }

  private let state = Mutex(State())
  private let session = RecognitionSession()
  @RecognitionActor private var finalized = false
  @RecognitionActor private let decoder: WindowDecoder
  @RecognitionActor private var diarizer: MeetingNemotronTrack?
  @RecognitionActor private var windows: [StoredWindow] = []
  @RecognitionActor private var slotIDs: [String: String] = [:]
  @RecognitionActor private let speakerModels: Nemotron3Models?
  private let singleSpeaker: Bool
  private var channel: String { singleSpeaker ? "microphone" : "system" }
  private let onUpdate: @MainActor @Sendable ([TranscriptSegment], Double) -> Void
  private let onFailure: @MainActor @Sendable (Error) -> Void
  private let onFinalize: @MainActor @Sendable ([TranscriptSegment], DiarizationAudit) -> Void

  @RecognitionActor init(
    model: ParakeetModel, speakerModels: Nemotron3Models?, singleSpeaker: Bool = false,
    onUpdate: @escaping @MainActor @Sendable ([TranscriptSegment], Double) -> Void,
    onFailure: @escaping @MainActor @Sendable (Error) -> Void,
    onFinalize: @escaping @MainActor @Sendable ([TranscriptSegment], DiarizationAudit) -> Void
  ) {
    decoder = WindowDecoder(model: model, singleSpeaker: singleSpeaker)
    self.speakerModels = speakerModels
    self.singleSpeaker = singleSpeaker
    self.onUpdate = onUpdate
    self.onFailure = onFailure
    self.onFinalize = onFinalize
  }

  @discardableResult
  func append(samples: [Float], at time: TimeInterval) -> Bool {
    state.withLock { value -> Bool in
      guard !session.cancelled, !value.finishing, value.failure == nil else { return false }
      do {
        try value.buffer.append(samples, at: time)
        schedule(&value)
        return true
      } catch {
        DiagnosticLog.shared.event(
          "pipeline", "append_failed",
          "track=\(channel) samples=\(samples.count) error_type=\(type(of: error))")
        value.failure = AppFailure("meeting.recognition-interrupted")
        value.buffer = MeetingAudioBuffer()
        schedule(&value)
        return false
      }
    }
  }

  private func schedule(_ value: inout State) {
    guard !value.scheduled else { return }
    value.scheduled = true
    Task { @RecognitionActor in await drain() }
  }

  func finish(completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
    DiagnosticLog.shared.event("pipeline", "finish_requested")
    state.withLock {
      $0.finishing = true
      $0.completion = completion
      schedule(&$0)
    }
  }

  func cancel() {
    DiagnosticLog.shared.event("pipeline", "cancel")
    session.cancel()
    state.withLock {
      $0.buffer = MeetingAudioBuffer()
      $0.completion = nil
    }
  }

  func waitForDrain() async {
    await withCheckedContinuation { continuation in
      state.withLock {
        if $0.scheduled { $0.waiters.append(continuation) } else { continuation.resume() }
      }
    }
  }

  @RecognitionActor private func stableTurns(
    _ raw: [SpeakerTurn]
  ) -> [SpeakerTurn] {
    raw.map { turn in
      let key = turn.id
      if slotIDs[key] == nil {
        slotIDs[key] = String(slotIDs.count + 1)
        DiagnosticLog.shared.event(
          "nemotron3-meeting", "speaker_assigned",
          "track=\(channel) raw=\(turn.id) stable=\(slotIDs[key]!)")
      }
      return SpeakerTurn(id: slotIDs[key]!, start: turn.start, end: turn.end)
    }
  }

  @RecognitionActor private func attribute(_ window: StoredWindow) -> [TranscriptSegment] {
    let raw = diarizer?.turns(in: window.start..<window.end) ?? []
    let turns = stableTurns(raw)
    var attribution = SpeakerAttribution(preserveRawIDs: true)
    return attribution.segments(
      tokens: window.tokens, turns: turns,
      start: window.start, end: window.end
    )
    .map { segment in
      TranscriptSegment(
        start: segment.start, end: segment.end,
        text: TranscriptCleanup.apply(segment.text), speakerID: segment.speakerID,
        channel: channel)
    }.filter { !$0.text.isEmpty }
  }

  @RecognitionActor private func finishSpeakers() throws -> (
    segments: [TranscriptSegment], audit: DiarizationAudit
  ) {
    try diarizer?.finish()
    if diarizer != nil {
      DiagnosticLog.shared.event("nemotron3-meeting", "final_flush", "track=\(channel)")
    }
    let rawTurns = diarizer?.allTurns() ?? []
    let turns = stableTurns(rawTurns).sorted { $0.start < $1.start }
    let tokens = windows.flatMap(\.tokens).sorted { $0.time < $1.time }
    let duration = max(
      windows.map(\.end).max() ?? 0,
      turns.map(\.end).max() ?? 0)
    var settings = OfflineTranscriptAligner.Settings()
    settings.renumberSpeakers = false
    let aligned = OfflineTranscriptAligner(settings: settings).detailedAlignment(
      tokens: tokens, turns: turns, duration: duration)
    let result = aligned.segments.map {
      TranscriptSegment(
        start: $0.start, end: $0.end, text: $0.text, speakerID: $0.speakerID, channel: channel)
    }
    // Align stable speaker slots while retaining the onset's raw channel and speaker ID for audit.
    let words = aligned.words.map { word in
      let raw = Set(
        rawTurns.filter { $0.start <= word.start && word.start < $0.end }.map(\.id))
      return DiarizationAudit.Word(
        text: word.text, start: word.start, end: word.end,
        rawSpeaker: raw.count == 1 ? "\(channel):\(raw.first!)" : nil,
        assignedSpeaker: word.assignedSpeaker, supportSeconds: word.supportSeconds,
        confidence: word.confidence, reason: word.reason)
    }
    let unknown = words.filter { $0.assignedSpeaker == nil }.count
    // Count assignments from the onset-based rule for comparison on actual meetings.
    let unknownByStart = words.filter { word in
      Set(turns.filter { $0.start <= word.start && word.start < $0.end }.map(\.id)).count != 1
    }.count
    var reasons: [String: Int] = [:]
    for word in words where word.reason != "matched" { reasons[word.reason, default: 0] += 1 }
    let speakerIDs = Set(result.compactMap(\.speakerID))
    DiagnosticLog.shared.event(
      "nemotron3-meeting", "final_alignment",
      "windows=\(windows.count) segments=\(result.count)"
        + " labeled=\(result.filter { $0.speakerID != nil }.count)"
        + " unknown=\(result.filter { $0.speakerID == nil }.count)"
        + " distinctSpeakers=\(speakerIDs.count)"
        + " words=\(words.count) unknown_words=\(unknown) unknown_words_by_start=\(unknownByStart)"
        + " reasons=\(reasons.sorted { $0.key < $1.key })")
    let audit = DiarizationAudit(
      source: L10n.text("history.meeting"), duration: duration, method: "nemotron3-fast32",
      words: words, rawTurns: turns,
      warnings: [],
      pipelineObservations: diarizer?.observations.sorted { $0.start < $1.start } ?? [],
      engineInfo: .init(
        name: "NVIDIA Nemotron 3 Diarization", preset: "fast32",
        modelRepository: "FluidInference/nemotron-3-diarization-coreml",
        fluidAudioCommit: "503b4bd1bbf7220882de39fe8ae6716aae4132da",
        speakerSlots: 8, outputFrameSeconds: 0.01,
        activityThreshold: 0.5, minimumTurnSeconds: 0.12))
    return (result, audit)
  }

  @RecognitionActor private func drain() async {
    while true {
      var terminalError: Error?
      var terminalCompletion: (@MainActor @Sendable (Result<Void, Error>) -> Void)?
      var terminal = false
      let item = state.withLock { value -> ([Float], AudioWindow, Double)? in
        if !session.cancelled, value.failure == nil,
          let batch = value.buffer.take(final: value.finishing)
        {
          return (batch.samples, batch.window, batch.offset)
        }
        value.scheduled = false
        terminalError = value.failure
        terminalCompletion = value.completion
        value.completion = nil
        terminal = value.finishing || value.failure != nil || session.cancelled
        if terminal { value.buffer = MeetingAudioBuffer() }
        for waiter in value.waiters { waiter.resume() }
        value.waiters.removeAll()
        return nil
      }
      guard let (samples, window, offset) = item else {
        if session.cancelled {
          diarizer = nil
          windows.removeAll()
          return
        }
        if terminal && !singleSpeaker && !finalized {
          finalized = true
          do {
            let final = try finishSpeakers()
            await onFinalize(final.segments, final.audit)
          } catch {
            terminalError = terminalError ?? error
            DiagnosticLog.shared.event(
              "nemotron3-meeting", "finalize_failed",
              "error_type=\(type(of: error))")
          }
        }
        if let error = terminalError {
          DiagnosticLog.shared.event("pipeline", "failed", "error_type=\(type(of: error))")
          await onFailure(error)
        }
        if let completion = terminalCompletion {
          await completion(terminalError.map { .failure($0) } ?? .success(()))
        }
        if terminal {
          diarizer = nil
          windows.removeAll()
          slotIDs.removeAll()
        }
        return
      }
      do {
        let decoded = try autoreleasepool {
          try decoder.decodeWithEvidence(
            samples: samples, window: window, offset: offset, session: session)
        }
        let segments: [TranscriptSegment]
        if singleSpeaker {
          segments = decoded.segments.map {
            TranscriptSegment(
              start: $0.start, end: $0.end, text: $0.text,
              speakerID: $0.speakerID, channel: channel)
          }
        } else {
          guard let models = speakerModels else {
            throw AppFailure("meeting.nemotron-3-is-not-loaded")
          }
          if diarizer == nil {
            diarizer = MeetingNemotronTrack(models: models, label: channel)
          }
          let ownedStart = offset + Double(window.keep.lowerBound) / 16_000
          let localStart = window.keep.lowerBound - window.read.lowerBound
          let localEnd = localStart + window.keep.count
          guard localStart >= 0, localEnd <= samples.count else {
            throw AppFailure("meeting.invalid-audio-window-bounds")
          }
          try diarizer?.append(
            samples: Array(samples[localStart..<localEnd]),
            at: ownedStart)
          let stored = StoredWindow(
            tokens: decoded.tokens,
            start: decoded.start, end: decoded.end)
          windows.append(stored)
          segments = attribute(stored)
        }
        if !session.cancelled {
          DiagnosticLog.shared.event(
            "pipeline", "decoded",
            "track=\(channel) segments=\(segments.count)"
              + " labeled=\(segments.filter { $0.speakerID != nil }.count)"
              + " unknown=\(segments.filter { $0.speakerID == nil }.count)"
              + " diarizer=\(singleSpeaker ? "disabled" : "nemotron3-fast32")")
          await onUpdate(segments, offset + Double(window.keep.upperBound) / 16_000)
        }
      } catch {
        DiagnosticLog.shared.event("pipeline", "decode_failed", "error_type=\(type(of: error))")
        state.withLock {
          $0.failure = error
          $0.buffer = MeetingAudioBuffer()
        }
      }
    }
  }
}
