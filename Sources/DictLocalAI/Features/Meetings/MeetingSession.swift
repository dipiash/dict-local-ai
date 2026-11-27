import AppKit
import Combine
import DictApplication
import DictCore
import Synchronization
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
  @Published private(set) var systemAudioSilenceMinutes: Int?
  @Published private(set) var progress: Double?
  @Published private(set) var saveError = ""
  @Published private(set) var selectedMeeting: UUID?
  @Published private(set) var unsaved = false
  var running: Bool { state != .idle }
  private let workflow: MeetingWorkflow
  private let makeCapture: () -> any MeetingCapturing
  private let ready: () -> Bool
  private let recognizer: any MeetingRecognizing
  private let preferences: Preferences
  private var capture: (any MeetingCapturing)?
  private var audio: HistoryAudioFile?
  private let silence = Mutex(SilentAudioMonitor())
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
    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.stop(reason: L10n.text("meeting.the-mac-went-to-sleep"), cause: .sleep)
        }
      })
    observers.append(
      DistributedNotificationCenter.default().addObserver(
        forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.stop(
            reason: L10n.text("meeting.the-screen-locked-meeting-recording"), cause: .screenLocked)
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
    DiagnosticLog.shared.event(
      "meeting", "start", "source=system audio=\(preferences.keepsAudio ? "saved" : "off")")
    silence.withLock { $0 = SilentAudioMonitor() }
    generation = UUID()
    let id = generation
    state = .preparing
    unsaved = false
    saveError = ""
    elapsed = 0
    systemAudioDetected = false
    systemAudioSilenceMinutes = nil
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
        // Capture the retention preference once so changes apply to the next recording.
        let audio = HistoryAudioFile.make(kind: .meeting, enabled: preferences.keepsAudio)
        self.audio = audio
        capture.onSamples = { [weak self] samples, time in
          _ = pipeline.append(samples: samples, at: time)
          audio?.write(samples, at: time)
          guard let event = self?.silence.withLock({ $0.append(samples, at: time) }) else { return }
          Task { @MainActor in self?.apply(silence: event, id: id) }
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
        var document = workflow.makeTranscript(
          title: L10n.text(
            "meeting.recording-title", startedAt.formatted(date: .numeric, time: .shortened)),
          startedAt: startedAt)
        document.audioFile = audio?.name
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
  private func apply(silence event: SilentAudioMonitor.Event, id: UUID) {
    guard generation == id, state == .recording else { return }
    switch event {
    case .warningRaised(let seconds):
      DiagnosticLog.shared.event(
        "meeting", "system_audio_silent",
        "seconds=\(seconds) audio_seen=\(systemAudioDetected)")
      // Allow initial digital silence while the call is getting started.
      if systemAudioDetected { systemAudioSilenceMinutes = seconds / 60 }
    case .warningProgress(let seconds):
      if systemAudioDetected { systemAudioSilenceMinutes = seconds / 60 }
    case .resumed(let seconds):
      DiagnosticLog.shared.event("meeting", "system_audio_resumed", "silent_seconds=\(seconds)")
      systemAudioSilenceMinutes = nil
    }
  }
  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.state == .recording else { return }
        self.elapsed = min(
          FileTranscript.maximumSeconds, Int(ProcessInfo.processInfo.systemUptime - self.began))
        if self.elapsed >= FileTranscript.maximumSeconds { self.stop(cause: .timeLimit) }
      }
    }
  }

  /// Stable codes for the log; the user-facing text travels separately in `reason`.
  enum StopCause: String {
    case requested
    case timeLimit = "time_limit"
    case sleep
    case screenLocked = "screen_locked"
    case capture, recognition
    case setupCancelled = "setup_cancelled"

    init(_ reason: MeetingWorkflow.StopReason) {
      switch reason {
      case .requested: self = .requested
      case .setupCancelled: self = .setupCancelled
      case .capture: self = .capture
      case .recognition: self = .recognition
      }
    }
  }

  func stop(reason: String? = nil, cause: StopCause? = nil) {
    stop(
      reason.map(MeetingWorkflow.StopReason.capture) ?? .requested,
      cause: cause)
  }

  private func stop(_ requestedReason: MeetingWorkflow.StopReason, cause: StopCause? = nil) {
    guard let reason = workflow.stop(state: state, reason: requestedReason) else { return }
    let logged = cause ?? StopCause(requestedReason)
    DiagnosticLog.shared.event("meeting", "stop", "reason=\(logged.rawValue) elapsed=\(elapsed)")
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

  // If queued record creation fails, there is no History entry to own the audio.
  private func recordExists() -> Bool {
    guard let id = selectedMeeting else { return false }
    do { return try workflow.read(id) != nil } catch { return true }
  }

  private func finished(reason: MeetingWorkflow.StopReason) {
    pipeline = nil
    preparation = nil
    systemAudioSilenceMinutes = nil
    var audioOutcome = audio == nil ? "off" : "kept"
    if !recordExists() {
      audio?.discard()
      transcript?.audioFile = nil
      if audio != nil { audioOutcome = "discarded" }
    } else if audio?.finalizeSynchronously() == false {
      transcript?.audioFile = nil
      audioOutcome = "empty"
    }
    audio = nil
    DiagnosticLog.shared.event(
      "meeting", "finished",
      "segments=\(transcript?.segments.count ?? 0) audio=\(audioOutcome) silent_at_stop_seconds=\(silence.withLock { $0.ongoingSilenceSeconds })"
    )
    workflow.finalize(&transcript, elapsed: elapsed, reason: reason)
    if selectedMeeting != nil && saveError.isEmpty { unsaved = false }
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
    // Finalize the file before quitting to preserve the end of the recording.
    if let audio {
      let began = ProcessInfo.processInfo.systemUptime
      _ = audio.finalizeSynchronously()
      let millis = Int((ProcessInfo.processInfo.systemUptime - began) * 1_000)
      DiagnosticLog.shared.event("history-audio", "quit_wait", "kind=meeting ms=\(millis)")
    }
    audio = nil
    let capture = capture
    Task { await capture?.stop() }
  }
}
