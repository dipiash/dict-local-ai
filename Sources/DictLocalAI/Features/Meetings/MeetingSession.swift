import AppKit
import Combine
import DictApplication
import DictCore
import UniformTypeIdentifiers

@MainActor
final class MeetingSession: ObservableObject {
  typealias State = MeetingWorkflow.State
  @Published private(set) var state: State = .idle
  @Published private(set) var transcript: FileTranscript?
  @Published private(set) var audit: DiarizationAudit?
  @Published private(set) var message = L10n.text("meeting.record-a-meeting-of-up")
  @Published private(set) var elapsed = 0
  @Published private(set) var systemAudioDetected = false
  @Published private(set) var progress: Double?
  @Published private(set) var saveError = ""
  @Published private(set) var savedMeetings: [SavedMeeting] = []
  @Published private(set) var selectedMeeting: UUID?
  @Published private(set) var unsaved = false
  var running: Bool { state != .idle }
  private let workflow: MeetingWorkflow
  private let makeCapture: () -> any MeetingCapturing
  private let ready: () -> Bool
  private let recognizer: any MeetingRecognizing
  private let preferences: Preferences
  private var capture: (any MeetingCapturing)?
  private var pipeline: (any MeetingRecognizingPipeline)?
  private var preparation: Task<Void, Never>?
  private var generation = UUID()
  private var began: TimeInterval = 0
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private var subscriptions = Set<AnyCancellable>()

  init(
    recognizer: any MeetingRecognizing, preferences: Preferences, workflow: MeetingWorkflow,
    makeCapture: @escaping () -> any MeetingCapturing, ready: @escaping () -> Bool
  ) {
    self.workflow = workflow
    self.makeCapture = makeCapture
    self.ready = ready
    self.recognizer = recognizer
    self.preferences = preferences
    reloadSaved()
    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.stop(reason: L10n.text("meeting.the-mac-went-to-sleep"))
        }
      })
    observers.append(
      DistributedNotificationCenter.default().addObserver(
        forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.stop(reason: L10n.text("meeting.the-screen-locked-meeting-recording"))
        }
      })
    preferences.$saveHistory.dropFirst().sink { [weak self] enabled in
      guard let self else { return }
      if let selected = self.workflow.setAutosave(
        enabled, state: self.state, elapsed: self.elapsed, transcript: self.transcript,
        onError: self.journalErrorHandler())
      {
        self.selectedMeeting = selected
      }
    }.store(in: &subscriptions)
  }

  private func journalErrorHandler() -> @MainActor @Sendable (Error) -> Void {
    { [weak self] error in
      self?.saveError = L10n.text("meeting.autosave-failed", L10n.error(error))
    }
  }

  func start() {
    guard workflow.begin(state: state, ready: ready) else {
      message = L10n.text("meeting.wait-for-the-model-and")
      return
    }
    DiagnosticLog.shared.event("meeting", "start", "source=system")
    generation = UUID()
    let id = generation
    state = .preparing
    unsaved = false
    saveError = ""
    elapsed = 0
    systemAudioDetected = false
    transcript = nil
    audit = nil
    selectedMeeting = nil
    message = L10n.text("meeting.preparing-models")
    preparation = Task { @MainActor in
      do {
        try Task.checkCancellation()
        let pipeline = try await recognizer.makeMeetingPipeline(
          onUpdate: { [weak self] segments, until in
            guard let self, self.generation == id else { return }
            self.workflow.append(
              segments, until: until, elapsed: self.elapsed, to: &self.transcript)
            self.unsaved = true
          },
          onFailure: { [weak self] error in
            guard let self, self.generation == id else { return }
            self.stop(.recognition(error))
          },
          onFinalize: { [weak self] segments, audit in
            guard let self, self.generation == id else { return }
            self.workflow.replaceSegments(segments, in: &self.transcript)
            self.audit = audit
          })
        guard generation == id, state == .preparing, !Task.isCancelled else {
          pipeline.cancel()
          return
        }
        self.pipeline = pipeline
        let capture = makeCapture()
        self.capture = capture
        capture.onSamples = { samples, time in
          _ = pipeline.append(samples: samples, at: time)
        }
        capture.onSystemAudioDetected = { [weak self] in
          guard let self, self.generation == id else { return }
          self.systemAudioDetected = true
        }
        capture.onFailure = { [weak self] reason in
          guard let self, self.generation == id else { return }
          self.stop(reason: reason)
        }
        let startedAt = Date()
        let document = workflow.makeTranscript(
          title: L10n.text(
            "meeting.recording-title", startedAt.formatted(date: .numeric, time: .shortened)),
          startedAt: startedAt)
        transcript = document
        selectedMeeting = workflow.beginAutosave(
          document, enabled: preferences.saveHistory, onError: journalErrorHandler())
        try await capture.start()
        try Task.checkCancellation()
        guard generation == id, state == .preparing else {
          await capture.stop()
          return
        }
        began = ProcessInfo.processInfo.systemUptime
        state = .recording
        progress = nil
        message = L10n.text("meeting.recording-and-recognizing")
        startTimer()
      } catch {
        guard generation == id else { return }
        stop(error is CancellationError ? .setupCancelled : .recognition(error))
      }
    }
  }
  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.state == .recording else { return }
        self.elapsed = min(
          FileTranscript.maximumSeconds, Int(ProcessInfo.processInfo.systemUptime - self.began))
        if self.elapsed >= FileTranscript.maximumSeconds { self.stop() }
      }
    }
  }

  func stop(reason: String? = nil) {
    stop(reason.map(MeetingWorkflow.StopReason.capture) ?? .requested)
  }

  private func stop(_ requestedReason: MeetingWorkflow.StopReason) {
    DiagnosticLog.shared.event(
      "meeting", "stop", "reason=\(requestedReason.isComplete ? "normal" : "error")")
    guard let reason = workflow.stop(state: state, reason: requestedReason) else { return }
    state = .finishing
    preparation?.cancel()
    timer?.invalidate()
    timer = nil
    progress = nil
    message = L10n.text("meeting.stopping-recording-and-processing-the")
    let id = generation
    let capture = capture
    Task { @MainActor in
      await capture?.stop()
      guard self.generation == id else { return }
      self.capture = nil
      guard let pipeline = self.pipeline else {
        self.finished(reason: reason)
        return
      }
      pipeline.finish { [weak self] result in
        guard let self, self.generation == id else { return }
        self.finished(reason: self.workflow.resolve(reason, result: result))
      }
    }
  }

  private func finished(reason: MeetingWorkflow.StopReason) {
    DiagnosticLog.shared.event("meeting", "finished", "segments=\(transcript?.segments.count ?? 0)")
    pipeline = nil
    preparation = nil
    workflow.finalize(&transcript, elapsed: elapsed, reason: reason)
    if selectedMeeting != nil && saveError.isEmpty { unsaved = false }
    reloadSaved()
    workflow.release()
    state = .idle
    switch reason {
    case .requested: message = L10n.text("meeting.meeting-finished-review-the-speakers")
    case .setupCancelled: message = L10n.text("meeting.setup-canceled")
    case .capture(let text): message = text
    case .recognition(let error): message = L10n.error(error)
    }
  }

  func rename(_ id: String, _ name: String) {
    guard !running else { return }
    transcript?.speakerNames[id] = name
    unsaved = true
  }
  func editSegment(_ index: Int, _ text: String) {
    guard !running, var document = transcript, document.editSegmentText(at: index, text: text)
    else { return }
    transcript = document
    unsaved = true
  }
  func reloadSaved() {
    do { savedMeetings = try workflow.saved() } catch {
      saveError = L10n.text("meeting.could-not-read-meetings", L10n.error(error))
    }
  }
  func openSaved(_ meeting: SavedMeeting) {
    guard !running else { return }
    do {
      guard let document = try workflow.read(meeting.id) else {
        throw AppFailure("meeting.this-meeting-file-contains-no")
      }
      transcript = document
      selectedMeeting = meeting.id
      unsaved = false
      saveError = ""
      message = L10n.text("meeting.saved-meeting-opened-you-can")
    } catch { saveError = L10n.error(error) }
  }
  func saveChanges() {
    guard !running, let transcript else { return }
    do {
      selectedMeeting = try workflow.save(transcript, to: selectedMeeting)
      unsaved = false
      saveError = ""
      message = L10n.text("meeting.meeting-changes-saved")
      reloadSaved()
    } catch { saveError = L10n.text("meeting.could-not-save-meeting", L10n.error(error)) }
  }
  func deleteSaved(_ meeting: SavedMeeting) {
    guard !running else { return }
    do {
      try workflow.delete(meeting.id)
      if selectedMeeting == meeting.id {
        transcript = nil
        selectedMeeting = nil
        unsaved = false
      }
      saveError = ""
      message = L10n.text("meeting.meeting-deleted")
      reloadSaved()
    } catch { saveError = L10n.error(error) }
  }
  func deleteSaved() {
    guard !running else { return }
    do {
      try workflow.deleteAll()
      if selectedMeeting != nil {
        transcript = nil
        selectedMeeting = nil
        unsaved = false
      }
      savedMeetings = []
      saveError = ""
      message = L10n.text("meeting.all-saved-meetings-deleted")
    } catch { saveError = L10n.error(error) }
  }
  func saveAudit() {
    guard !running, let audit else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "meeting-diarization-audit.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try audit.json().write(to: url, options: .atomic)
      message = L10n.text("files.diagnostics-saved", "\(url.lastPathComponent)")
    } catch {
      message = L10n.text("files.could-not-save-diagnostics", L10n.error(error))
    }
  }

  func save(_ format: String) {
    guard let transcript, !running else { return }
    do {
      if let url = try TranscriptExporter.save(transcript, format: format, basename: "meeting") {
        if selectedMeeting == nil { unsaved = false }
        message = L10n.text("dictation.saved", "\(url.lastPathComponent)")
      }
    } catch { message = L10n.error(error) }
  }
  func shutdown() {
    preparation?.cancel()
    pipeline?.cancel()
    timer?.invalidate()
    workflow.shutdown(elapsed: elapsed)
    let capture = capture
    Task { await capture?.stop() }
  }
}
