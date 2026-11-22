import AppKit
import Combine
import DictApplication
import DictCore

@MainActor
final class DictationSession: ObservableObject {
  let preferences: Preferences
  private let workflow: DictationWorkflow
  private let historySaved: @MainActor () -> Void
  private let historySaveFailed: @MainActor (Error) -> Void
  let hotkeys: Hotkeys
  private let services: any DictationRecognizing
  private var lease: ModeCoordinator.Lease?
  var ready: () -> Bool = { false }
  @Published private(set) var transcript: FileTranscript?
  private var pipeline: (any DictationRecognizingPipeline)?
  private var preparation: Task<Void, Never>?
  private var pendingFinish = false
  private var preparingMicrophone = false
  private var audioRequestID = UUID()
  @Published private(set) var phase = DictationPhase.idle
  @Published private(set) var message = ""
  @Published private(set) var text = ""
  @Published var scratchpad = ""
  var internalEditorFocused = false
  private var internalEditorWasTarget = false
  @Published private(set) var elapsed = 0
  @Published private(set) var level: Float = 0
  @Published private(set) var handsFree = false
  @Published private(set) var noticeIsSuccess = false
  var onShowPanel: () -> Void = {}
  var onHidePanel: () -> Void = {}
  var onShowActionResult: () -> Void = {}
  var onHideActionResult: () -> Void = {}
  var onOpenSettings: () -> Void = {}
  var canShowLastResult: Bool { phase == .result && !text.isEmpty }
  var canExportTXT: Bool { !scratchpad.isEmpty || canShowLastResult }
  var canExportJSON: Bool { phase == .result && transcript?.segments.isEmpty == false }
  private var noticeDismissTask: Task<Void, Never>?
  private let makeAudio: (@escaping @MainActor @Sendable () -> Void) -> any DictationCapturing
  private lazy var audio = makeAudio { [weak self] in
    self?.interrupt(reason: L10n.text("dictation.the-microphone-changed-or-disconnected"))
  }
  private var session: RecognitionSession?
  private var sentSamples = 0
  private var startedAt: TimeInterval = 0
  private var timer: Timer?
  private var subscriptions = Set<AnyCancellable>()
  private var observers: [NSObjectProtocol] = []
  private var completionTarget: InsertionTarget?
  private var allowInsertion = true
  private var lastWindowUpdate = 0.0

  init(
    preferences: Preferences, hotkeys: Hotkeys, recognizer: any DictationRecognizing,
    makeAudio: @escaping (@escaping @MainActor @Sendable () -> Void) -> any DictationCapturing,
    workflow: DictationWorkflow, historySaved: @escaping @MainActor () -> Void,
    historySaveFailed: @escaping @MainActor (Error) -> Void
  ) {
    self.preferences = preferences
    self.workflow = workflow
    self.makeAudio = makeAudio
    self.historySaved = historySaved
    self.historySaveFailed = historySaveFailed
    self.hotkeys = hotkeys
    self.services = recognizer
    hotkeys.onStart = { [weak self] in self?.start(handsFree: false) }
    hotkeys.onFinish = { [weak self] in self?.finish() }
    hotkeys.onToggle = { [weak self] in self?.toggle() }
    hotkeys.onCancel = { [weak self] in self?.cancel() }
    hotkeys.isBusy = { [weak self] in self?.phase == .recording || self?.phase == .processing }
    hotkeys.onUnavailable = { [weak self] in
      self?.interrupt(reason: L10n.text("dictation.keyboard-input-was-interrupted-recording"))
    }
    preferences.$hold.sink { [weak self] in self?.hotkeys.hold = $0 }.store(in: &subscriptions)
    preferences.$toggle.sink { [weak self] in self?.hotkeys.toggle = $0 }.store(in: &subscriptions)
    preferences.$enabled.sink { [weak self] enabled in
      self?.hotkeys.enabled = enabled
      if !enabled { self?.cancel() }
    }.store(in: &subscriptions)
    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.interrupt(reason: L10n.text("dictation.the-mac-went-to-sleep"))
        }
      })
    observers.append(
      DistributedNotificationCenter.default().addObserver(
        forName: NSNotification.Name("com.apple.screenIsLocked"),
        object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.interrupt(reason: L10n.text("dictation.the-screen-locked-you-can"))
        }
      })
    timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    _ = hotkeys.install()
  }
  func start(handsFree: Bool) {
    guard let acquired = workflow.start(enabled: preferences.enabled, phase: phase) else {
      DiagnosticLog.shared.event("dictation", "start_rejected", "phase=\(phase)")
      return
    }
    noticeDismissTask?.cancel()
    onHideActionResult()
    onHidePanel()
    completionTarget = nil
    internalEditorWasTarget = false
    DiagnosticLog.shared.event("dictation", "start", "target=deferred_until_finish")
    lease = acquired
    guard ready() else {
      workflow.release(lease)
      showActionMessage(L10n.text("dictation.download-a-model-in-settings"))
      return
    }
    guard SystemPermissions.microphone == .authorized else {
      workflow.release(lease)
      showActionMessage(L10n.text("dictation.allow-microphone-access-in-the"))
      return
    }
    guard SystemPermissions.accessibility else {
      workflow.release(lease)
      showActionMessage(L10n.text("dictation.allow-accessibility-access-in-the"))
      return
    }
    let current = RecognitionSession()
    audioRequestID = UUID()
    let requestID = audioRequestID
    session = current
    phase = .processing
    pendingFinish = false
    preparingMicrophone = false
    message = L10n.text("dictation.preparing-to-record")
    lastWindowUpdate = ProcessInfo.processInfo.systemUptime
    onShowPanel()
    preparation = Task {
      do {
        let engine = try await services.makeDictationPipeline(
          onUpdate: { [weak self] segments, end in
            guard let self, self.session === current, !current.cancelled else { return }
            self.transcript?.segments.append(contentsOf: segments)
            self.transcript?.processedUntil = end
            self.lastWindowUpdate = ProcessInfo.processInfo.systemUptime
            DiagnosticLog.shared.event(
              "dictation", "decoded", "segments=\(segments.count) until=\(end)")
          },
          onFailure: { [weak self] error in
            guard let self, self.session === current, !current.cancelled else { return }
            self.interrupt(reason: L10n.error(error))
          })
        guard self.session === current, !current.cancelled else {
          engine.cancel()
          return
        }
        pipeline = engine
        DiagnosticLog.shared.event("dictation", "models_ready")
        preparingMicrophone = true
        DiagnosticLog.shared.event("dictation", "microphone_start_requested")
        let selectedDevice = preferences.microphone
        // Core Audio can block while opening the input node.
        Task { [weak self] in
          try? await Task.sleep(for: .seconds(10))
          guard let self, self.session === current, self.preparingMicrophone else { return }
          DiagnosticLog.shared.event("audio", "engine_start_timeout", "after=10s")
          self.interrupt(
            reason:
              L10n.text("dictation.the-microphone-did-not-start"))
        }
        try await audio.start(deviceID: selectedDevice, requestID: requestID)
        guard self.session === current, !current.cancelled, !Task.isCancelled else {
          await audio.stop(requestID: requestID, discard: false)
          return
        }
        preparingMicrophone = false
        DiagnosticLog.shared.event("dictation", "microphone_started")
        self.handsFree = handsFree
        startedAt = ProcessInfo.processInfo.systemUptime
        elapsed = 0
        level = 0
        text = ""
        transcript = FileTranscript(source: L10n.text("menu.dictation-label"), duration: 0)
        transcript?.startedAt = Date()
        message = L10n.text("dictation.listening")
        sentSamples = 0
        allowInsertion = true
        phase = .recording
        onShowPanel()
        if pendingFinish { finish() }
      } catch {
        guard self.session === current else { return }
        preparingMicrophone = false
        DiagnosticLog.shared.event("dictation", "start_failed", "error=\(type(of: error))")
        self.pipeline?.cancel()
        self.pipeline = nil
        self.session = nil
        await self.audio.stop(requestID: requestID, discard: false)
        self.workflow.release(lease)
        self.lease = nil
        showActionMessage(L10n.error(error))
      }
    }
  }
  func toggle() {
    DiagnosticLog.shared.event(
      "dictation", "hotkey_toggle", "phase=\(phase) handsFree=\(handsFree)")
    if phase == .recording {
      if handsFree { finish() } else { handsFree = true }
    } else if phase == .processing, pipeline == nil || preparingMicrophone {
      DiagnosticLog.shared.event("dictation", "cancel_preparation_by_toggle")
      cancel()
    } else if phase.canStart {
      start(handsFree: true)
    }
  }
  private var ticks = 0
  private func tick() {
    ticks += 1
    guard phase == .recording, session != nil else { return }
    elapsed = min(
      DictationWorkflow.maximumSeconds, Int(ProcessInfo.processInfo.systemUptime - startedAt))
    level = audio.level
    let delta = audio.copy(from: sentSamples)
    sentSamples += delta.count
    if !delta.isEmpty {
      let accepted = pipeline?.append(
        samples: delta, at: Double(sentSamples - delta.count) / 16_000)
      if accepted == false { DiagnosticLog.shared.event("dictation", "audio_backpressure") }
    }
    if elapsed > 15, ticks % 25 == 0,
      ProcessInfo.processInfo.systemUptime - lastWindowUpdate > 25
    {
      DiagnosticLog.shared.event("dictation", "asr_no_updates", "elapsed=\(elapsed)")
    }
    if workflow.shouldFinish(elapsed: elapsed, sampleCount: audio.count) { finish() }
  }
  func finish() {
    if phase == .processing, pipeline == nil || preparingMicrophone {
      pendingFinish = true
      return
    }
    guard phase == .recording, let session else { return }
    completionTarget = TextInsertion.target()
    internalEditorWasTarget = internalEditorFocused && NSApp.isActive
    DiagnosticLog.shared.event(
      "dictation", "finish",
      "samples=\(audio.count) target=\(completionTarget == nil ? "none" : "present")")
    phase = .processing
    message = L10n.text("dictation.recognizing")
    level = 0
    let requestID = audioRequestID
    Task { [weak self] in
      guard let self else { return }
      await self.audio.stop(requestID: requestID, discard: false)
      guard self.session === session, !session.cancelled else { return }
      let tail = self.audio.copy(from: self.sentSamples)
      self.sentSamples += tail.count
      if !tail.isEmpty {
        _ = self.pipeline?.append(
          samples: tail,
          at: Double(self.sentSamples - tail.count) / 16_000)
      }
      self.complete(session)
    }
  }
  private func complete(_ current: RecognitionSession) {
    DiagnosticLog.shared.event("dictation", "recognition_finishing", "samples=\(sentSamples)")
    pipeline?.finish { [weak self] result in
      guard let self, self.session === current else { return }
      switch result {
      case .success:
        let duration = Double(self.sentSamples) / 16_000
        let completion = DictationCompletion(transcript: self.transcript, duration: duration)
        self.workflow.release(self.lease)
        self.pipeline = nil
        self.audio.erase()
        self.session = nil
        self.text = completion?.text ?? ""
        guard let completion else {
          self.transcript?.duration = duration
          self.transcript?.complete = true
          self.showTransientNotice(
            L10n.text("dictation.no-speech-detected"), duration: .milliseconds(2600))
          return
        }
        self.transcript = completion.transcript
        let (outcome, history) = self.workflow.finish(
          completion, saveHistory: self.preferences.saveHistory,
          insert: { text in
            self.allowInsertion
              ? TextInsertion.insert(text, target: self.completionTarget) : .unavailable
          },
          insertInEditor: { text in
            self.allowInsertion && self.internalEditorWasTarget && self.internalEditorFocused
              && TextInsertion.insertInFocusedLocalEditor(text)
          },
          copy: { text in
            let copied = TextInsertion.copy(text)
            DiagnosticLog.shared.event(
              "insertion", "fallback_clipboard", "success=\(copied) chars=\(text.count)")
            return copied
          })
        switch history {
        case .success: self.historySaved()
        case .failure(let error): self.historySaveFailed(error)
        case nil: break
        }
        DiagnosticLog.shared.event(
          "dictation", "completed",
          "chars=\(completion.text.count) insertion=\(outcome) completion_target=\(self.completionTarget == nil ? "none" : "present")"
        )
        switch outcome {
        case .inserted:
          self.showTransientNotice(
            L10n.text("dictation.text-inserted-a-copy-is"), duration: .milliseconds(1800),
            success: true, preserveResult: true)
        case .pasteRequested:
          // Showing the result window here can interrupt a pending paste.
          self.showTransientNotice(
            L10n.text("dictation.paste-requested-check-the-target"),
            duration: .milliseconds(3000), preserveResult: true)
        case .copied:
          self.showTransientNotice(
            L10n.text("dictation.could-not-confirm-the-target"),
            duration: .seconds(6), preserveResult: true)
        case .retained:
          self.phase = .result
          self.message = L10n.text("dictation.could-not-paste-or-update")
          self.onHidePanel()
          self.onShowActionResult()
        }
      case .failure(let error):
        DiagnosticLog.shared.event("dictation", "recognition_failed", "error=\(type(of: error))")
        self.workflow.release(self.lease)
        self.pipeline?.cancel()
        self.pipeline = nil
        self.phase = .failed
        self.message = L10n.text("dictation.recognition-failed", L10n.error(error))
        self.onHidePanel()
        self.onShowActionResult()
      }
    }
  }
  func retry() {
    guard workflow.canRetry(phase: phase) else { return }
    guard audio.count > 0 else {
      cancel()
      showTransientNotice(
        L10n.text("dictation.the-recording-has-no-audio"), duration: .milliseconds(2600))
      return
    }
    guard let acquired = workflow.retry() else { return }
    lease = acquired
    session?.cancel()
    let current = RecognitionSession()
    session = current
    noticeDismissTask?.cancel()
    onHideActionResult()
    allowInsertion = false
    completionTarget = nil
    transcript = FileTranscript(
      source: L10n.text("menu.dictation-label"), duration: Double(audio.count) / 16_000)
    phase = .processing
    message = L10n.text("dictation.recognizing-again")
    onShowPanel()
    preparation = Task {
      do {
        let engine = try await services.makeDictationPipeline(
          onUpdate: { [weak self] segments, end in
            guard let self, self.session === current, !current.cancelled else { return }
            self.transcript?.segments.append(contentsOf: segments)
            self.transcript?.processedUntil = end
            self.lastWindowUpdate = ProcessInfo.processInfo.systemUptime
            DiagnosticLog.shared.event(
              "dictation", "decoded", "segments=\(segments.count) until=\(end)")
          },
          onFailure: { [weak self] error in
            guard let self, self.session === current, !current.cancelled else { return }
            self.interrupt(reason: L10n.error(error))
          })
        guard self.session === current, !current.cancelled else {
          engine.cancel()
          return
        }
        pipeline = engine
        sentSamples = audio.count
        let samples = audio.copy(from: 0)
        for start in stride(from: 0, to: samples.count, by: 64_000) {
          guard !current.cancelled else { return }
          _ = engine.append(
            samples: Array(samples[start..<min(start + 64_000, samples.count)]),
            at: Double(start) / 16_000)
          await engine.waitForDrain()
        }
        complete(current)
      } catch {
        guard self.session === current else { return }
        workflow.release(lease)
        phase = .failed
        message = L10n.error(error)
        onHidePanel()
        onShowActionResult()
      }
    }
  }
  func interrupt(reason: String) {
    DiagnosticLog.shared.event("dictation", "interrupted", "phase=\(phase)")
    guard phase == .recording || phase == .processing else { return }
    preparingMicrophone = false
    pendingFinish = false
    let requestID = audioRequestID
    Task { await audio.stop(requestID: requestID, discard: false) }
    session?.cancel()
    pipeline?.cancel()
    pipeline = nil
    preparation?.cancel()
    hotkeys.reset()
    allowInsertion = false
    completionTarget = nil
    workflow.release(lease)
    phase = .interrupted
    message = reason
    level = 0
    onHidePanel()
    onShowActionResult()
  }
  func cancel() {
    noticeDismissTask?.cancel()
    DiagnosticLog.shared.event("dictation", "cancel", "phase=\(phase)")
    preparingMicrophone = false
    pendingFinish = false
    session?.cancel()
    session = nil
    workflow.release(lease)
    transcript = nil
    let requestID = audioRequestID
    Task { await audio.stop(requestID: requestID, discard: true) }
    pipeline?.cancel()
    pipeline = nil
    preparation?.cancel()
    phase = .idle
    text = ""
    message = ""
    level = 0
    completionTarget = nil
    hotkeys.reset()
    onHidePanel()
    onHideActionResult()
  }
  func save(_ format: String) {
    do {
      let destination: URL?
      switch format {
      case "txt":
        guard canExportTXT else { return }
        let visibleText = scratchpad.isEmpty ? text : scratchpad
        destination = try TranscriptExporter.savePlainText(visibleText, basename: "dictation")
      case "json":
        guard canExportJSON, let transcript else { return }
        destination = try TranscriptExporter.save(transcript, format: "json", basename: "dictation")
      default:
        return
      }
      if let destination {
        message = L10n.text("dictation.saved", "\(destination.lastPathComponent)")
      }
    } catch { message = L10n.error(error) }
  }
  func reopenLatestResult() {
    guard canShowLastResult else { return }
    noticeDismissTask?.cancel()
    onHidePanel()
    onShowActionResult()
  }

  func copyResult() {
    guard !text.isEmpty else { return }
    if TextInsertion.copy(text) {
      message = L10n.text("dictation.text-copied-select-the-target")
    } else {
      message = L10n.text("dictation.could-not-update-the-clipboard")
      DiagnosticLog.shared.event("insertion", "manual_copy_failed")
    }
  }

  func dismissResult() {
    guard phase == .result || phase == .failed || phase == .interrupted else { return }
    if phase == .failed || phase == .interrupted {
      cancel()
      return
    }
    noticeDismissTask?.cancel()
    phase = .idle
    text = ""
    transcript = nil
    message = ""
    onHidePanel()
    onHideActionResult()
  }

  private func showActionMessage(_ value: String) {
    noticeDismissTask?.cancel()
    DiagnosticLog.shared.event("dictation", "action_message", "chars=\(value.count)")
    phase = .result
    text = ""
    noticeIsSuccess = false
    message = value
    onHidePanel()
    onShowActionResult()
  }

  private func showTransientNotice(
    _ value: String, duration: Duration, success: Bool = false,
    preserveResult: Bool = false
  ) {
    noticeDismissTask?.cancel()
    DiagnosticLog.shared.event("dictation", "notice", "chars=\(value.count)")
    noticeIsSuccess = success
    phase = .result
    message = value
    onHideActionResult()
    onShowPanel()
    noticeDismissTask = Task { [weak self] in
      do {
        try await Task.sleep(for: duration)
      } catch { return }
      guard let self, self.phase == .result else { return }
      if preserveResult {
        self.onHidePanel()
      } else {
        self.dismissResult()
      }
    }
  }
  func shutdown() {
    cancel()
    timer?.invalidate()
    hotkeys.shutdown()
  }
}
