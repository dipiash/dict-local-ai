import AVFoundation
import Combine
import DictApplication
import DictCore

@MainActor
final class AppServices: ObservableObject {
  let preferences = Preferences(storage: PreferencesFactory.make())
  let history = HistoryStore(
    history: RecordingHistory(repository: { try RecordingDatabase.require() }))
  let hotkeys = Hotkeys()
  let modes = ModeCoordinator()
  private let recognizer = RecognitionService()
  @Published private(set) var ready = false
  @Published private(set) var speakerModelsReady = false
  @Published private(set) var installingModel: ManagedModel?
  @Published private(set) var installing = false
  @Published private(set) var setupMessage = L10n.text("models.manage-models-in-the-models")
  @Published private(set) var progress: Double?
  @Published private(set) var router = AppRouter()
  @Published private(set) var sidebarToggleRequest = 0
  func requestSidebarToggle() { sidebarToggleRequest &+= 1 }
  private var pendingNavigationSource: UsageTelemetry.Source = .sidebar

  func openWorkspace(_ section: WorkspaceSection, source: UsageTelemetry.Source = .internalAction) {
    if source != .sidebar {
      UsageTelemetry.navigationRequested(to: section, source: source)
    }
    let decision = router.request(section, historyHasUnsavedEdits: history.draftDirty)
    if decision == .confirmationRequired {
      pendingNavigationSource = source
      DiagnosticLog.shared.event("history-ui", "navigation_blocked_unsaved")
      return
    }
    logNavigation(decision, source: source)
  }

  func reopenWorkspace(source: UsageTelemetry.Source = .dock) {
    logNavigation(router.reopen(), source: source)
  }

  func closeWorkspace() { router.close() }

  func cancelPendingNavigation() { router.cancelPending() }

  func resolvePendingNavigation(save: Bool) {
    guard let requested = router.pendingSection else { return }
    if save {
      guard history.saveDraft() else { return }
    } else {
      history.discardDraft()
    }
    if pendingNavigationSource != .sidebar {
      UsageTelemetry.navigationRequested(to: requested, source: pendingNavigationSource)
    }
    guard let decision = router.confirmPending() else { return }
    logNavigation(decision, source: pendingNavigationSource)
  }

  private func logNavigation(_ decision: AppRouter.Decision, source: UsageTelemetry.Source) {
    guard case .navigated(let from, let to) = decision else { return }
    UsageTelemetry.navigate(from: from, to: to, source: source, changed: from != to)
  }

  @Published var hotkeysReady = false
  @Published private(set) var microphoneStatus = SystemPermissions.microphone
  @Published private(set) var accessibilityGranted = SystemPermissions.accessibility
  @Published private(set) var accessibilityRequested = false
  @Published private(set) var inputMonitoringRequested = false
  @Published private(set) var inputMonitoringGranted = SystemPermissions.inputMonitoring
  lazy var dictation: DictationSession = {
    let session = DictationSession(
      preferences: preferences, hotkeys: hotkeys, recognizer: recognizer,
      makeAudio: AudioCapture.init(onInterruption:),
      workflow: DictationWorkflow(modes: modes, writer: { try RecordingDatabase.require() }),
      historySaved: history.didSaveHistory,
      historySaveFailed: { [history] in history.reportSaveFailure($0, category: .dictation) })
    session.ready = { [weak self] in self?.ready == true }
    return session
  }()
  lazy var files = FileTranscriptionSession(
    recognizer: recognizer,
    workflow: FileTranscriptionWorkflow(modes: modes, writer: { try RecordingDatabase.require() }),
    preferences: preferences,
    historySaved: history.didSaveHistory,
    historySaveFailed: { [history] in history.reportSaveFailure($0, category: .file) },
    inspectDuration: AudioFileReader.inspectDuration,
    ready: { [weak self] in self?.ready == true },
    speakerModelsReady: { [weak self] in self?.speakerModelsReady == true })
  lazy var meeting = MeetingSession(
    recognizer: recognizer, preferences: preferences,
    workflow: MeetingWorkflow(modes: modes, journal: MeetingJournal()),
    makeCapture: MeetingAudioCapture.init,
    ready: { [weak self] in self?.ready == true && self?.speakerModelsReady == true })

  private var lastHotkeyInstallAttempt: TimeInterval = -.infinity
  private var didLogInitialPermissions = false

  private func reportProgress(_ value: Double?, _ message: String) {
    progress = value
    setupMessage = message
  }

  private lazy var modelSetup = ModelSetup(
    environment: HuggingFaceModelEnvironment(recognizer: recognizer))

  func modelRevision(_ kind: ManagedModel) -> String? {
    HuggingFaceModels.read(kind)?.revision
  }

  func restoreModels() {
    guard !installing else { return }
    installing = true
    Task { @MainActor in
      defer { installing = false }
      await modelSetup.restore(ManagedModel.allCases) { kind, event in
        switch event {
        case .checking:
          reportProgress(nil, L10n.text("models.checking-local-files", kind.title))
        case .invalidReceipt:
          DiagnosticLog.shared.event(
            "models", "receipt_verification_failed", "model=\(kind.rawValue)")
        case .loaded:
          markModelReady(kind)
        case .failed(let error):
          DiagnosticLog.shared.event(
            "models", "restore_failed", "model=\(kind.rawValue) error_type=\(type(of: error))")
        }
      }
      reportProgress(
        nil,
        L10n.text(
          "models.local-status",
          L10n.text(ready ? "common.ready" : "common.not-ready"),
          L10n.text(speakerModelsReady ? "common.ready" : "common.not-ready"))
          + (ready && speakerModelsReady
            ? "" : " " + L10n.text("models.install-or-reinstall-models-in")))
    }
  }

  func installModel(_ kind: ManagedModel) {
    guard !installing, modes.active == nil else { return }
    installing = true
    installingModel = kind
    progress = 0
    Task { @MainActor in
      defer {
        installing = false
        installingModel = nil
      }
      do {
        let revision = try await modelSetup.install(kind) { [weak self] event in
          guard let self, self.installingModel == kind else { return }
          switch event {
          case .revision(let revision):
            self.reportProgress(0, "\(kind.title): Hugging Face \(revision.prefix(12))…")
          case .downloading(let fraction, let title):
            guard let previous = self.progress, let fraction, fraction >= previous else { return }
            self.reportProgress(fraction, "\(title) — \(Int(fraction * 100))%")
          case .checking:
            self.reportProgress(
              nil, L10n.text("models.checking-and-loading-local-files", kind.title))
          }
        }
        markModelReady(kind)
        DiagnosticLog.shared.event("models", "installed", "model=\(kind.rawValue) sha=\(revision)")
        reportProgress(1, L10n.text("models.is-installed-you-can-use", kind.title))
      } catch {
        DiagnosticLog.shared.event(
          "models", "installation_failed", "model=\(kind.rawValue) error_type=\(type(of: error))")
        reportProgress(
          nil, L10n.text("models.installation-error", kind.title, L10n.error(error)))
      }
    }
  }

  private func markModelReady(_ kind: ManagedModel) {
    switch kind {
    case .ultra: ready = true
    case .nemotron: speakerModelsReady = true
    }
  }

  func requestMicrophone() {
    guard SystemPermissions.microphone == .notDetermined else {
      openPrivacy("Privacy_Microphone")
      refreshPermissions()
      return
    }
    Task {
      await SystemPermissions.requestMicrophone()
      refreshPermissions()
    }
  }
  func requestAccessibility() {
    guard !SystemPermissions.accessibility else {
      refreshPermissions()
      return
    }
    if accessibilityRequested {
      openPrivacy("Privacy_Accessibility")
      return
    }
    accessibilityRequested = true
    SystemPermissions.requestAccessibility()
    refreshPermissions()
  }
  func requestInputMonitoring() {
    guard !SystemPermissions.inputMonitoring else {
      refreshPermissions()
      return
    }
    if inputMonitoringRequested {
      openPrivacy("Privacy_ListenEvent")
      return
    }
    inputMonitoringRequested = true
    SystemPermissions.requestInputMonitoring()
    refreshPermissions()
  }
  // Core Audio has no public preflight check for this permission.
  func openSystemAudioPrivacy() {
    openPrivacy("Privacy_ScreenCapture")
  }

  func openPrivacy(_ anchor: String) { SystemPermissions.openPrivacy(anchor) }
  func refreshPermissions() {
    let previous = (
      microphoneStatus, accessibilityGranted,
      inputMonitoringGranted, hotkeysReady
    )
    // macOS has no single change event for these permissions.
    let microphone = SystemPermissions.microphone
    if microphoneStatus != microphone { microphoneStatus = microphone }
    let accessibility = SystemPermissions.accessibility
    if accessibilityGranted != accessibility {
      accessibilityGranted = accessibility
      accessibilityRequested = false
      if !accessibility { hotkeys.shutdown() }
    }
    let inputMonitoring = SystemPermissions.inputMonitoring
    if inputMonitoringGranted != inputMonitoring {
      inputMonitoringGranted = inputMonitoring
      inputMonitoringRequested = false
    }
    var keysReady = hotkeys.isInstalled
    let now = ProcessInfo.processInfo.systemUptime
    if !keysReady, now - lastHotkeyInstallAttempt >= 5 {
      lastHotkeyInstallAttempt = now
      keysReady = hotkeys.install()
    }
    if hotkeysReady != keysReady { hotkeysReady = keysReady }
    let changed =
      previous.0 != microphoneStatus || previous.1 != accessibilityGranted
      || previous.2 != inputMonitoringGranted || previous.3 != hotkeysReady
    if !didLogInitialPermissions || changed {
      let event = didLogInitialPermissions ? "changed" : "initial"
      didLogInitialPermissions = true
      DiagnosticLog.shared.event(
        "permissions", event,
        "mic=\(microphoneStatus.rawValue) ax=\(accessibilityGranted) system_audio=not_queryable input=\(inputMonitoringGranted) hotkeys=\(hotkeysReady)"
      )
    }
  }
  func shutdown() {
    history.audio.stop()
    meeting.shutdown()
    files.shutdown()
    dictation.shutdown()
  }
}
