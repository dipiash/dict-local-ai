import AppKit
import Combine
import DictApplication
import DictCore
import UniformTypeIdentifiers

@MainActor
final class FileTranscriptionSession: ObservableObject {
  @Published private(set) var running = false
  private(set) var unsaved = false
  @Published private(set) var transcript: FileTranscript?
  @Published private(set) var message = L10n.text("files.choose-an-audio-recording-up")
  @Published private(set) var canRetry = false
  private var lastFileURL: URL?
  private var latestImportedAudio: HistoryAudioFile?
  @Published var identifySpeakers = true
  @Published var compareChunks = true
  @Published private(set) var audit: DiarizationAudit?
  @Published private(set) var reviewCandidates: [DiarizationAudit.PipelineObservation] = []
  @Published private(set) var splitCandidates: [DiarizationSplitReview.Candidate] = []
  private var preparation: Task<Void, Never>?
  private var session: RecognitionSession?
  private let recognizer: any FileRecognizing
  private let inspectDuration: @Sendable (URL) async throws -> Double
  private let workflow: FileTranscriptionWorkflow
  private let historySaved: @MainActor () -> Void
  private let historySaveFailed: @MainActor (Error) -> Void
  private let preferences: Preferences
  private let ready: () -> Bool
  private let speakerModelsReady: () -> Bool

  init(
    recognizer: any FileRecognizing, workflow: FileTranscriptionWorkflow, preferences: Preferences,
    historySaved: @escaping @MainActor () -> Void,
    historySaveFailed: @escaping @MainActor (Error) -> Void,
    inspectDuration: @escaping @Sendable (URL) async throws -> Double,
    ready: @escaping () -> Bool, speakerModelsReady: @escaping () -> Bool
  ) {
    self.recognizer = recognizer
    self.workflow = workflow
    self.inspectDuration = inspectDuration
    self.historySaved = historySaved
    self.historySaveFailed = historySaveFailed
    self.preferences = preferences
    self.ready = ready
    self.speakerModelsReady = speakerModelsReady
  }

  func chooseFile() {
    guard !running else { return }
    if let blocker = workflow.blocker(
      ready: ready, identifySpeakers: identifySpeakers, speakerModelsReady: speakerModelsReady)
    {
      switch blocker {
      case .speechModel: message = L10n.text("files.install-parakeet-ultra-in-settings")
      case .speakerModels: message = L10n.text("files.set-up-nemotron-3-in")
      case .activeRecording: message = L10n.text("files.finish-the-current-recording-before")
      }
      return
    }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.audio]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    startFile(url)
  }

  func retryFile() {
    guard canRetry, let lastFileURL else { return }
    startFile(lastFileURL)
  }

  private func startFile(_ url: URL) {
    guard !running,
      workflow.begin(
        ready: ready, identifySpeakers: identifySpeakers, speakerModelsReady: speakerModelsReady)
    else { return }
    lastFileURL = url
    canRetry = false
    audit = nil
    reviewCandidates = []
    splitCandidates = []
    DiagnosticLog.shared.event(
      "file", "start",
      "type=\(url.pathExtension) asr=parakeet-ultra")
    let current = RecognitionSession()
    session = current
    running = true
    unsaved = false
    transcript = workflow.makeTranscript(
      source: url.lastPathComponent, duration: 0, identifySpeakers: identifySpeakers)
    message = L10n.text("files.reading-the-file")
    let scoped = url.startAccessingSecurityScopedResource()
    preparation = Task { @MainActor in
      do {
        let duration = try await inspectDuration(url)
        try Task.checkCancellation()
        transcript = workflow.makeTranscript(
          source: url.lastPathComponent, duration: duration, identifySpeakers: identifySpeakers)
        let output = try await recognizer.transcribeFile(
          url, session: current,
          identifySpeakers: identifySpeakers,
          compareChunks: identifySpeakers && compareChunks,
          update: {
            [weak self] duration, end, segments in
            guard let self, self.session === current else { return }
            self.workflow.append(
              segments, source: url.lastPathComponent, duration: duration, until: end,
              identifySpeakers: self.identifySpeakers, to: &self.transcript)
            if end > 0 { self.unsaved = true }
            DiagnosticLog.shared.event("file", "update", "end=\(end) segments=\(segments.count)")
            if !current.cancelled { self.message = L10n.text("files.recognizing-words") }
          },
          stage: { [weak self] stage in
            guard let self, self.session === current, !current.cancelled else { return }
            self.message = stage
          })
        guard self.session === current, !current.cancelled else { throw CancellationError() }
        workflow.apply(output, duration: duration, to: &transcript)
        audit = output.audit
        splitCandidates = output.splitCandidates
        reviewCandidates = output.reviewCandidates
        if scoped { url.stopAccessingSecurityScopedResource() }
        complete(.success(()), session: current)
      } catch {
        if scoped { url.stopAccessingSecurityScopedResource() }
        complete(.failure(current.cancelled ? CancellationError() : error), session: current)
      }
    }
  }
  private func complete(_ result: Result<Void, Error>, session current: RecognitionSession) {
    guard session === current else { return }
    let completion = workflow.finish(
      result, transcript: &transcript, identifySpeakers: identifySpeakers)
    running = false
    session = nil
    preparation = nil
    DiagnosticLog.shared.event(
      "file", "finished",
      "outcome=\(completion.diagnosticOutcome) segments=\(transcript?.segments.count ?? 0) processed=\(transcript?.processedUntil ?? 0) duration=\(transcript?.duration ?? 0)"
    )
    canRetry = completion.retryable && lastFileURL != nil
    switch completion {
    case .success:
      message = L10n.text("files.done-review-the-speakers-and")
    case .warnings:
      message = L10n.text("files.done-with-recognition-warnings-check")
    case .speechOnly:
      message = L10n.text("files.done-recognized-text-without-speaker")
    case .cancelled:
      message = L10n.text("files.canceled-you-can-save-the")
    case .failed(let error):
      message = L10n.text("files.error-you-can-save-the", L10n.error(error))
    case .diarizationFailed(let error):
      message = L10n.text("files.could-not-identify-speakers-you", L10n.error(error))
    }
    var wasCancelled = false
    if case .cancelled = completion { wasCancelled = true }
    let audio =
      preferences.keepsAudio && transcript?.segments.isEmpty == false
      ? lastFileURL.flatMap { url in
        HistoryAudioFile.copy(
          from: url, enabled: preferences.keepsAudio,
          limitSeconds: wasCancelled ? transcript?.processedUntil : nil,
          onUnreadable: { [weak self] name in
            MainActor.assumeIsolated {
              if self?.transcript?.audioFile == name { self?.transcript?.audioFile = nil }
            }
          })
      } : nil
    transcript?.audioFile = audio?.name
    latestImportedAudio = audio
    do {
      if try workflow.saveIfEligible(transcript, enabled: preferences.saveHistory) {
        historySaved()
      } else {
        audio?.discard()
        transcript?.audioFile = nil
      }
    } catch {
      audio?.discard()
      transcript?.audioFile = nil
      historySaveFailed(error)
    }
  }

  func renameSpeaker(_ id: String, name: String) {
    guard !running, var document = transcript,
      FileSpeakerEdits.rename(id, name: name, in: &document)
    else { return }
    transcript = document
    unsaved = true
  }

  func assignSpeaker(_ index: Int, _ newSpeaker: String?) {
    guard !running, var document = transcript else { return }
    let previous =
      document.segments.indices.contains(index) ? document.segments[index].speakerID : nil
    guard FileSpeakerEdits.assign(newSpeaker, at: index, in: &document) else { return }
    transcript = document
    unsaved = true
    DiagnosticLog.shared.event(
      "diarization", "manual_speaker_override",
      "segment=\(index) from=\(previous ?? "unknown") to=\(newSpeaker ?? "unknown")")
  }

  func addSpeaker(_ index: Int) {
    guard let transcript else { return }
    assignSpeaker(index, FileSpeakerEdits.nextID(in: transcript))
  }

  func confirmSameSpeaker(_ candidateIndex: Int) {
    guard !running, splitCandidates.indices.contains(candidateIndex), let transcript else {
      return
    }
    let candidate = splitCandidates[candidateIndex]
    let edited = SpeakerReviewEdits.mergeEpisode(transcript.segments, candidate: candidate)
    guard edited.changed > 0 else {
      message =
        L10n.text("files.there-are-no-complete-segments")
      return
    }
    self.transcript?.segments = edited.segments
    unsaved = true
    message = L10n.text("files.updated-segments-in-this-episode", Int64(edited.changed))
    DiagnosticLog.shared.event(
      "diarization", "human_confirmed_local_merge",
      "at=\(candidate.transition) from=\(candidate.afterSpeaker) to=\(candidate.beforeSpeaker) segments=\(edited.changed)"
    )
    splitCandidates.remove(at: candidateIndex)
  }

  func cancel() {
    guard running else { return }
    session?.cancel()
    preparation?.cancel()
    message = L10n.text("files.canceling")
  }
  func shutdown() {
    cancel()
    // Stop a long import at the next minute boundary during shutdown.
    latestImportedAudio?.finalizeBeforeExit()
  }
  func saveAudit() {
    guard !running, let audit else { return }
    let panel = NSSavePanel()
    let name = URL(fileURLWithPath: audit.source).deletingPathExtension().lastPathComponent
    panel.nameFieldStringValue = name + "-diarization-audit.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try audit.json().write(to: url, options: .atomic)
      DiagnosticLog.shared.event("file", "audit_export_success")
      message = L10n.text("files.diagnostics-saved", "\(url.lastPathComponent)")
    } catch {
      DiagnosticLog.shared.event("file", "audit_export_failed", "error_type=\(type(of: error))")
      message = L10n.text("files.could-not-save-diagnostics", L10n.error(error))
    }
  }

  func save(_ format: String) {
    guard let transcript, !running, transcript.processedUntil > 0 else { return }
    let base = URL(fileURLWithPath: transcript.source).deletingPathExtension().lastPathComponent
    do {
      if let url = try TranscriptExporter.save(transcript, format: format, basename: base) {
        DiagnosticLog.shared.event("file", "export_success", "format=\(format)")
        unsaved = false
        message = L10n.text("dictation.saved", "\(url.lastPathComponent)")
      }
    } catch {
      DiagnosticLog.shared.event(
        "file", "export_failed", "format=\(format) error_type=\(type(of: error))")
      message = L10n.text("files.could-not-save", L10n.error(error))
    }
  }
}
