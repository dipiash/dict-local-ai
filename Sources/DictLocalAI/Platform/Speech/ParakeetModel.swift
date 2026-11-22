import CoreML
import DictApplication
import DictCore
import FluidAudio
import Foundation
import Synchronization

@RecognitionActor
final class ParakeetModel {
  private let frontEnd: MLModel
  private let acoustic: MLModel
  private let prediction: MLModel
  private let decision: MLModel
  private let vocabulary: [String: String]
  private let blank = 8192

  init(directory: URL) throws {
    let config = MLModelConfiguration()
    config.computeUnits = .cpuAndNeuralEngine
    func load(_ file: String) throws -> MLModel {
      try MLModel(
        contentsOf: directory.appendingPathComponent(file + ".mlmodelc"), configuration: config)
    }
    frontEnd = try load("Preprocessor")
    acoustic = try load("Encoder")
    prediction = try load("Decoder")
    decision = try load("JointDecisionv3")
    vocabulary = try JSONDecoder().decode(
      [String: String].self,
      from: Data(contentsOf: HuggingFaceModels.ultraVocabularyURL(in: directory)))
  }

  private func tensor(_ shape: [Int], type: MLMultiArrayDataType = .float32) throws -> MLMultiArray
  {
    let array = try MLMultiArray(shape: shape.map(NSNumber.init(value:)), dataType: type)
    memset(array.dataPointer, 0, array.count * (type == .double ? 8 : 4))
    return array
  }
  private func array(_ result: MLFeatureProvider, _ name: String) throws -> MLMultiArray {
    guard let value = result.featureValue(for: name)?.multiArrayValue else {
      throw AppFailure("recognition.the-model-returned-an-unexpected", "\(name)")
    }
    return value
  }
  private func evaluate(_ model: MLModel, _ values: [String: Any]) throws -> MLFeatureProvider {
    try model.prediction(from: MLDictionaryFeatureProvider(dictionary: values))
  }
  private func decoder(token: Int, hidden: MLMultiArray, cell: MLMultiArray) throws -> (
    MLMultiArray, MLMultiArray, MLMultiArray
  ) {
    let input = try tensor([1, 1], type: .int32)
    input[0] = NSNumber(value: token)
    let length = try tensor([1], type: .int32)
    length[0] = 1
    let out = try evaluate(
      prediction, ["targets": input, "target_length": length, "h_in": hidden, "c_in": cell])
    return try (array(out, "decoder"), array(out, "h_out"), array(out, "c_out"))
  }

  func decode(samples: [Float], window: AudioWindow, cancelled: () -> Bool) throws -> String {
    try decodeTokens(samples: samples, window: window, cancelled: cancelled).map(\.piece).joined()
  }
  func decodeTokens(
    samples: [Float], window: AudioWindow, cancelled: () -> Bool,
    includeContext: Bool = false
  ) throws -> [RecognizedToken] {
    guard samples.count <= 240_000 else {
      throw AppFailure("recognition.the-audio-segment-is-larger")
    }
    if samples.isEmpty || samples.allSatisfy({ abs($0) < 0.0001 }) { return [] }
    let signal = try tensor([1, 240_000])
    let pointer = signal.dataPointer.bindMemory(to: Float.self, capacity: signal.count)
    samples.withUnsafeBufferPointer { source in
      if let base = source.baseAddress { pointer.update(from: base, count: source.count) }
    }
    let length = try tensor([1], type: .int32)
    length[0] = NSNumber(value: samples.count)
    let features = try evaluate(frontEnd, ["audio_signal": signal, "audio_length": length])
    let encoded = try evaluate(
      acoustic, ["mel": array(features, "mel"), "mel_length": array(features, "mel_length")])
    let frames = try array(encoded, "encoder")
    guard frames.shape.count == 3 else {
      throw AppFailure("recognition.unexpected-model-dimensions")
    }
    let frameCount = min(try array(encoded, "encoder_length")[0].intValue, frames.shape[2].intValue)
    var (state, hidden, cell) = try decoder(
      token: blank, hidden: tensor([2, 1, 640]), cell: tensor([2, 1, 640]))
    let channels = frames.shape[1].intValue
    let frameInput = try tensor([1, channels, 1])
    var output: [RecognizedToken] = []
    var frame = 0
    var emissions = 0
    while frame < frameCount {
      if cancelled() { throw CancellationError() }
      for channel in 0..<channels {
        frameInput[channel] = frames[[0, NSNumber(value: channel), NSNumber(value: frame)]]
      }
      let joined = try evaluate(decision, ["encoder_step": frameInput, "decoder_step": state])
      let token = try array(joined, "top_k_ids")[0].intValue
      var advance = max(0, try array(joined, "duration")[0].intValue)
      if token == blank {
        advance = max(1, advance)
      } else {
        if includeContext || window.owns(frame: frame), let piece = vocabulary[String(token)],
          !(piece.hasPrefix("<") && piece.hasSuffix(">"))
        {
          output.append(
            RecognizedToken(
              time: Double(window.read.lowerBound + frame * AudioWindow.frameSamples) / 16_000,
              piece: piece.replacingOccurrences(of: "▁", with: " ")))
        }
        (state, hidden, cell) = try decoder(token: token, hidden: hidden, cell: cell)
        emissions += 1
        if emissions >= 8 { advance = max(1, advance) }
      }
      if advance > 0 { emissions = 0 }
      frame += advance
    }
    return output
  }
}

@globalActor actor RecognitionActor {
  static let shared = RecognitionActor()
}

struct WindowSpeechResult: Sendable {
  let segments: [TranscriptSegment]
  let tokens: [RecognizedToken]
  let start: Double
  let end: Double
}

@RecognitionActor
final class WindowDecoder {
  private let model: ParakeetModel
  private var wordBoundaries = WordBoundarySelector()
  private let singleSpeaker: Bool

  init(model: ParakeetModel, singleSpeaker: Bool = false) {
    self.model = model
    self.singleSpeaker = singleSpeaker
  }

  func decode(
    samples: [Float], window: AudioWindow, offset: Double,
    session: RecognitionSession
  ) throws -> [TranscriptSegment] {
    try decodeWithEvidence(samples: samples, window: window, offset: offset, session: session)
      .segments
  }

  func decodeWithEvidence(
    samples: [Float], window: AudioWindow, offset: Double,
    session: RecognitionSession
  ) throws -> WindowSpeechResult {
    if session.cancelled { throw CancellationError() }
    let began = ProcessInfo.processInfo.systemUptime
    let allTokens = try model.decodeTokens(
      samples: samples, window: window, cancelled: { session.cancelled },
      includeContext: true
    ).map { RecognizedToken(time: $0.time + offset, piece: $0.piece) }
    let selected = wordBoundaries.select(
      tokens: allTokens,
      start: offset + Double(window.keep.lowerBound) / 16_000,
      end: offset + Double(window.keep.upperBound) / 16_000,
      hasRightContext: window.read.upperBound > window.keep.upperBound)
    let energy =
      samples.isEmpty
      ? 0
      : sqrt(
        samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
    DiagnosticLog.shared.event(
      "asr", "window",
      "raw_tokens=\(allTokens.count) selected_tokens=\(selected.tokens.count)"
        + " rms=\(String(format: "%.4f", energy))"
        + " seconds=\(String(format: "%.2f", ProcessInfo.processInfo.systemUptime - began))")
    if singleSpeaker {
      let value = TranscriptCleanup.apply(selected.tokens.map(\.piece).joined())
      let segments =
        value.isEmpty
        ? []
        : [
          TranscriptSegment(
            start: selected.start, end: selected.end, text: value, speakerID: "1")
        ]
      return WindowSpeechResult(
        segments: segments, tokens: selected.tokens,
        start: selected.start, end: selected.end)
    }
    return WindowSpeechResult(
      segments: [], tokens: selected.tokens,
      start: selected.start, end: selected.end)
  }
}

@RecognitionActor
final class RecognitionService {
  nonisolated init() {}
  private var model: ParakeetModel?
  private var nemotronModels: Nemotron3Models?
  private var meetingNemotronModels: Nemotron3Models?
  func load(_ directory: URL, publish: @Sendable () throws -> Void = {}) throws {
    let model = try ParakeetModel(directory: directory)
    let warmup = [Float](repeating: 0.001, count: 1280)
    if let window = AudioWindow.next(start: 0, available: warmup.count, final: true) {
      _ = try model.decode(samples: warmup, window: window, cancelled: { false })
    }
    try publish()
    self.model = model
  }

  func loadSpeakerModels(
    _ directory: URL, publish: @Sendable () throws -> Void = {}
  ) async throws {
    let meeting = try await Nemotron3Models.load(config: .fast32, directory: directory)
    let file = try await Nemotron3Models.load(config: .fast128, directory: directory)
    try publish()
    meetingNemotronModels = meeting
    nemotronModels = file
  }

  func makePipeline(
    singleSpeaker: Bool = false,
    onUpdate: @escaping @MainActor @Sendable ([TranscriptSegment], Double) -> Void,
    onFailure: @escaping @MainActor @Sendable (Error) -> Void,
    onFinalize: @escaping @MainActor @Sendable ([TranscriptSegment], DiarizationAudit) -> Void = {
      _, _ in
    }
  ) async throws -> MeetingRecognitionPipeline {
    guard let model else {
      throw AppFailure("recognition.the-speech-recognition-model-is")
    }
    if !singleSpeaker, meetingNemotronModels == nil {
      throw AppFailure("recognition.nemotron-3-fast32-is-not")
    }
    return MeetingRecognitionPipeline(
      model: model, speakerModels: singleSpeaker ? nil : meetingNemotronModels,
      singleSpeaker: singleSpeaker,
      onUpdate: onUpdate, onFailure: onFailure, onFinalize: onFinalize)
  }
  func transcribeFile(
    _ url: URL, session: RecognitionSession,
    identifySpeakers: Bool = true,
    compareChunks: Bool = false,
    update: @escaping @MainActor @Sendable (Double, Double, [TranscriptSegment]) -> Void,
    stage: @escaping @MainActor @Sendable (String) -> Void
  ) async throws -> FileRecognitionOutput {
    if model == nil {
      throw AppFailure("recognition.parakeet-ultra-is-not-installed")
    }
    let reader = try AudioFileReader(url: url)
    let duration = reader.duration
    let pipelineStarted = ProcessInfo.processInfo.systemUptime
    let asrStarted = pipelineStarted
    DiagnosticLog.shared.event(
      "performance", "file_pipeline_start",
      "duration_seconds=\(duration) voice_review=\(compareChunks)")
    DiagnosticLog.shared.event("file", "decode_begin", "duration=\(reader.duration)")
    await update(reader.duration, 0, [])

    var boundaries = WordBoundarySelector()
    var recognized: [RecognizedToken] = []
    let asrWarnings: [String] = []
    guard let model else { throw AppFailure("recognition.parakeet-is-not-ready") }
    var cursor = 0
    while let window = AudioWindow.next(start: cursor, available: reader.sampleCount, final: true) {
      if session.cancelled { throw CancellationError() }
      try Task.checkCancellation()
      let began = ProcessInfo.processInfo.systemUptime
      let all = try autoreleasepool {
        try model.decodeTokens(
          samples: reader.read(window.read, session: session),
          window: window, cancelled: { session.cancelled }, includeContext: true)
      }
      let selected = boundaries.select(
        tokens: all,
        start: Double(window.keep.lowerBound) / Double(AudioWindow.sampleRate),
        end: Double(window.keep.upperBound) / Double(AudioWindow.sampleRate),
        hasRightContext: window.read.upperBound > window.keep.upperBound)
      recognized.append(contentsOf: selected.tokens)
      DiagnosticLog.shared.event(
        "asr", "file_window",
        "raw_tokens=\(all.count) selected_tokens=\(selected.tokens.count) "
          + "seconds=\(String(format: "%.2f", ProcessInfo.processInfo.systemUptime - began))")
      let preview = TranscriptCleanup.apply(selected.tokens.map(\.piece).joined())
      let segments: [TranscriptSegment] =
        preview.isEmpty
        ? []
        : [
          TranscriptSegment(start: selected.start, end: selected.end, text: preview)
        ]
      await update(
        reader.duration, min(reader.duration, Double(window.keep.upperBound) / 16_000), segments)
      cursor = window.keep.upperBound
    }
    DiagnosticLog.shared.event(
      "performance", "file_asr_complete",
      "seconds=\(ProcessInfo.processInfo.systemUptime - asrStarted) audio_seconds=\(duration) tokens=\(recognized.count)"
    )
    DiagnosticLog.shared.event(
      "asr", "file_engine", "engine=parakeet-ultra tokens=\(recognized.count)")
    if session.cancelled { throw CancellationError() }
    try Task.checkCancellation()
    await stage(L10n.text("recognition.preparing-the-transcript-and-timestamps"))
    let aligner = OfflineTranscriptAligner()
    guard identifySpeakers else {
      DiagnosticLog.shared.event(
        "performance", "file_pipeline_complete",
        "audio_seconds=\(duration) wall_seconds=\(ProcessInfo.processInfo.systemUptime - pipelineStarted) voice_review=false"
      )
      DiagnosticLog.shared.event("file", "asr_only", "tokens=\(recognized.count)")
      return FileRecognitionOutput(
        segments: aligner.align(
          tokens: recognized, turns: [], duration: reader.duration,
          useSpeakers: false),
        diarizationMethod: "asr-only", audit: nil, asrWarnings: asrWarnings,
        splitCandidates: [])
    }

    guard let nemotronModels else {
      throw AppFailure("recognition.nemotron-3-fast128-is-not")
    }
    DiagnosticLog.shared.event("nemotron3", "model_ready", "preset=fast128 cached=true")
    if session.cancelled { throw CancellationError() }
    try Task.checkCancellation()
    await stage(L10n.text("recognition.finding-speakers-across-the-full"))
    let source = try FileAudioSampleSource(url: url, session: session)
    let diarizer = NemotronFileDiarizer(models: nemotronModels)
    let full: NemotronFileDiarizer.Output
    let globalNemotronStarted = ProcessInfo.processInfo.systemUptime
    do {
      full = try diarizer.run(source: source, session: session, diagnostic: true)
    } catch {
      if session.cancelled || error is CancellationError { throw CancellationError() }
      DiagnosticLog.shared.event("nemotron3", "full_run_failed", "error=\(type(of: error))")
      throw AppFailure("recognition.nemotron-3-could-not-finish", L10n.error(error))
    }
    let turns = full.turns
    DiagnosticLog.shared.event(
      "performance", "file_diarization_complete",
      "seconds=\(ProcessInfo.processInfo.systemUptime - globalNemotronStarted) turns=\(turns.count)"
    )
    DiagnosticLog.shared.event(
      "nemotron3", "full_summary", "turns=\(turns.count) duration=\(reader.duration)")
    await stage(L10n.text("recognition.matching-words-to-speaker-segments"))
    let aligned = aligner.detailedAlignment(
      tokens: recognized, turns: turns, duration: reader.duration)
    let unknown = aligned.words.filter { $0.assignedSpeaker == nil }
    var reasonCounts: [String: Int] = [:]
    for word in unknown { reasonCounts[word.reason, default: 0] += 1 }
    DiagnosticLog.shared.event(
      "diarization", "alignment_summary",
      "words=\(aligned.words.count) unknown=\(unknown.count) reasons=\(reasonCounts.sorted { $0.key < $1.key })"
    )

    var diagnostics = full.observations
    var comparison: [DiarizationAudit.ChunkRun] = []
    var warnings: [String] = asrWarnings
    let missingSpeech = UnassignedSpeechReview.find(words: aligned.words)
    for item in missingSpeech {
      diagnostics.append(
        .init(
          start: item.start, end: item.end,
          stage: "nemotron3_unassigned_asr_speech",
          metrics: ["words": Double(item.words)],
          note:
            "ASR produced text but Nemotron assigned no speaker; may be quiet speech or ASR hallucination"
        ))
      DiagnosticLog.shared.event(
        "nemotron3", "unassigned_asr_speech",
        "start=\(item.start) end=\(item.end) words=\(item.words)")
    }
    if !missingSpeech.isEmpty {
      let preview = missingSpeech.prefix(6).map {
        FileTranscript.segmentTime($0.start)
      }.joined(separator: ", ")
      warnings.append(
        L10n.text("recognition.unassigned-speech-warning", String(missingSpeech.count), preview)
      )
    }
    if compareChunks {
      for length in [180, 600] where Double(length) < reader.duration {
        let replayStarted = ProcessInfo.processInfo.systemUptime
        let rate = AudioWindow.sampleRate
        // Extra replay windows did not improve speaker labels.
        let offsets = [0]
        for offset in offsets {
          await stage(
            L10n.text("recognition.nemotron-3-diagnostics-1-min", "\(length / 60)", "\(offset)"))
          var firstSample = offset * rate
          while firstSample < source.sampleCount {
            if session.cancelled { throw CancellationError() }
            try Task.checkCancellation()
            let count = min(length * rate, source.sampleCount - firstSample)
            if count < 2 * rate { break }
            let start = Double(firstSample) / Double(rate)
            let end = Double(firstSample + count) / Double(rate)
            do {
              let piece = try diarizer.run(
                source: source, firstSample: firstSample, sampleCount: count,
                session: session, diagnostic: false)
              let local = piece.turns.map {
                SpeakerTurn(id: $0.id, start: $0.start + start, end: $0.end + start)
              }
              let coverage = DiarizationCoverage.wordCoverage(
                tokens: recognized, turns: local, start: start, end: end)
              let countSpeakers = Set(local.map(\.id)).count
              comparison.append(
                .init(
                  windowSeconds: Double(length), start: start, end: end,
                  turns: local, distinctSpeakers: countSpeakers,
                  wordCoverage: coverage,
                  clusteringThreshold: Double(NemotronFileDiarizer.threshold)))
              diagnostics.append(
                .init(
                  start: start, end: end, stage: "nemotron3_comparison",
                  metrics: [
                    "windowSeconds": Double(length),
                    "localSpeakers": Double(countSpeakers),
                    "turns": Double(local.count), "wordCoverage": coverage,
                    "wallSeconds": piece.seconds,
                  ], note: "Independent replay; speaker IDs do not correspond to the main run"))
              DiagnosticLog.shared.event(
                "nemotron3", "comparison_complete",
                "window=\(length) start=\(start) turns=\(local.count) coverage=\(coverage)")
            } catch {
              if session.cancelled || error is CancellationError { throw CancellationError() }
              warnings.append("Nemotron window \(length)s at \(start): \(type(of: error))")
              DiagnosticLog.shared.event(
                "nemotron3", "comparison_failed", "window=\(length) start=\(start)")
            }
            firstSample += count
          }
        }
        DiagnosticLog.shared.event(
          "performance", "file_replay_complete",
          "window_seconds=\(length) wall_seconds=\(ProcessInfo.processInfo.systemUptime - replayStarted)"
        )
      }
    }
    let disagreements = DiarizationDisagreement.find(main: turns, comparisons: comparison)
    for item in disagreements {
      diagnostics.append(
        .init(
          start: item.start, end: item.end,
          stage: "nemotron3_speaker_disagreement",
          metrics: [
            "dominantSupportSeconds": item.dominantSupportSeconds,
            "alternateSupportSeconds": item.alternateSupportSeconds,
            "comparisonStart": item.windowStart,
            "comparisonEnd": item.windowEnd,
          ],
          note:
            "REVIEW ONLY: full=\(item.mainSpeaker) local primary=\(item.dominantLocalSpeaker) local alternate=\(item.alternateLocalSpeaker)"
        ))
      DiagnosticLog.shared.event(
        "nemotron3", "speaker_disagreement",
        "start=\(item.start) end=\(item.end) full=\(item.mainSpeaker)"
          + " local=\(item.alternateLocalSpeaker) window=\(item.windowStart)-\(item.windowEnd)")
    }
    let consensus = DiarizationReviewConsensus.group(disagreements)
    for candidate in consensus {
      let classification = candidate.classification.rawValue
      diagnostics.append(
        .init(
          start: candidate.start, end: candidate.end,
          stage: "nemotron3_candidate_\(classification)",
          metrics: [
            "independentWindows": Double(candidate.windowCount),
            "candidateSeconds": candidate.end - candidate.start,
          ],
          note:
            "REVIEW ONLY: full=\(candidate.mainSpeaker); classification=\(classification); temporal comparison, not acoustic verification; do not automatically relabel"
        ))
      DiagnosticLog.shared.event(
        "nemotron3", "candidate_\(classification)",
        "start=\(candidate.start) end=\(candidate.end) windows=\(candidate.windowCount)")
    }
    let possibleSplits = DiarizationSplitReview.find(main: turns, comparisons: comparison)
    for item in possibleSplits {
      diagnostics.append(
        .init(
          start: item.start, end: item.end,
          stage: "nemotron3_possible_false_split",
          metrics: [
            "transition": item.transition,
            "independentWindows": Double(item.supportingWindows),
          ],
          note:
            "REVIEW ONLY: candidate same voice \(item.beforeSpeaker) -> \(item.afterSpeaker); local replay numbers are not identities"
        ))
      DiagnosticLog.shared.event(
        "nemotron3", "possible_false_split",
        "at=\(item.transition) before=\(item.beforeSpeaker) after=\(item.afterSpeaker) windows=\(item.supportingWindows)"
      )
    }
    let audit = DiarizationAudit(
      source: url.lastPathComponent, duration: reader.duration,
      method: NemotronFileDiarizer.method,
      words: aligned.words, rawTurns: turns, chunkRuns: comparison,
      warnings: warnings, pipelineObservations: diagnostics,
      engineInfo: .init(
        name: "NVIDIA Nemotron 3 Diarization",
        preset: "fast128",
        modelRepository: "FluidInference/nemotron-3-diarization-coreml",
        fluidAudioCommit: "503b4bd1bbf7220882de39fe8ae6716aae4132da",
        speakerSlots: 8, outputFrameSeconds: 0.01,
        activityThreshold: Double(NemotronFileDiarizer.threshold),
        minimumTurnSeconds: Double(NemotronFileDiarizer.minimumTurnSeconds)))
    DiagnosticLog.shared.event(
      "performance", "file_pipeline_complete",
      "audio_seconds=\(duration) wall_seconds=\(ProcessInfo.processInfo.systemUptime - pipelineStarted) "
        + "transcript_segments=\(aligned.segments.count) voice_review=\(compareChunks)")
    return FileRecognitionOutput(
      segments: aligned.segments,
      diarizationMethod: NemotronFileDiarizer.method, audit: audit,
      asrWarnings: asrWarnings, splitCandidates: possibleSplits)
  }
}
