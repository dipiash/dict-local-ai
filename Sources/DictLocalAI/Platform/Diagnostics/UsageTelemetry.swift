import DictCore
import Foundation

enum UsageTelemetry {
  enum Screen: String {
    case workspace, settings, dictation, files, meeting, history, models, about, tray
  }

  enum Source: String {
    case launch, tray, sidebar, keyboard, dock, internalAction, system, recordingPanel
  }

  enum Action: String {
    case chooseFile, replaceFile, retryFile, cancelFile
    case toggleSpeakers, toggleSpeakerReview, confirmSpeakerMerge, dismissSpeakerMerge
    case copyTranscript, exportTXT, exportJSON, exportAudit
    case startMeeting, stopMeeting, confirmNewMeeting, cancelNewMeeting
    case saveEdits, refreshHistory, clearHistoryPrompt, clearHistoryConfirm
    case deleteEntryPrompt, deleteEntryConfirm, selectEntry
    case removeAllAudioPrompt, removeAllAudioConfirm
    case openLogs = "open_logs"
    case modelInstall, modelReinstall
    case toggleSidebar, changeSettingsTab, toggleSetup, refreshMicrophones
    case captureHoldShortcut, captureToggleShortcut, restoreShortcuts
    case toggleEnabled, toggleHistory, toggleHistoryPlayback, toggleClipboardRestore
    case selectMicrophone, setHoldShortcut, setToggleShortcut
    case selectMeetingSource, startHandsFree, openLastDictation, quit
    case manualCopy, dismissResult, openPrivacySettings, copyResultToEditor, clearScratchpad
    case retryDictation, cancelDictation, stopDictation
    case assignSpeaker, addSpeaker, clearSpeaker, confirmSpeakerName, commitTextEdit,
      toggleLaunchOnLogin
  }

  static func navigationRequested(to: WorkspaceSection, source: Source) {
    DiagnosticLog.shared.event(
      "usage", "navigation_requested", "to=\(to.rawValue) source=\(source.rawValue)")
  }

  static func settingsRequested(_ tab: String) {
    let allowed: Set<String> = [
      "general", "permissions", "models", "shortcuts", "microphone", "storage", "startup",
    ]
    guard allowed.contains(tab) else { return }
    DiagnosticLog.shared.event("usage", "settings_requested", "tab=\(tab)")
  }

  static func sectionVisible(_ section: WorkspaceSection) {
    DiagnosticLog.shared.event("usage", "section_selected", "section=\(section.rawValue)")
  }

  static func sidebarVisibility(_ value: String) {
    guard value == "hidden" || value == "visible" else { return }
    DiagnosticLog.shared.event("usage", "sidebar_visibility", "state=\(value)")
  }

  static func navigate(from: WorkspaceSection, to: WorkspaceSection, source: Source, changed: Bool)
  {
    DiagnosticLog.shared.event(
      "usage", "navigation",
      "from=\(from.rawValue) to=\(to.rawValue) source=\(source.rawValue) changed=\(changed)")
  }

  static func action(_ screen: Screen, _ action: Action) {
    DiagnosticLog.shared.event(
      "usage", "action", "screen=\(screen.rawValue) name=\(action.rawValue)")
  }

  static func action(_ screen: Screen, _ action: Action, value: Bool) {
    DiagnosticLog.shared.event(
      "usage", "setting_changed",
      "screen=\(screen.rawValue) name=\(action.rawValue) value=\(value ? "on" : "off")")
  }

  static func action(_ screen: Screen, _ action: Action, choice: String) {
    // Log only fixed choices, such as “system” or “custom”.
    let approved: Set<String> = [
      "system", "custom", "microphone", "both", "general", "permissions", "models", "shortcuts",
      "storage", "startup", "microphone",
    ]
    guard approved.contains(choice) else { return }
    DiagnosticLog.shared.event(
      "usage", "setting_changed",
      "screen=\(screen.rawValue) name=\(action.rawValue) choice=\(choice)")
  }

  enum Lifecycle: String {
    case workspaceOpen, workspaceClose, appActivated, appDeactivated
    case windowMinimized, windowRestored
  }

  static func lifecycle(_ event: Lifecycle, section: WorkspaceSection) {
    DiagnosticLog.shared.event(
      "usage", "lifecycle", "name=\(event.rawValue) section=\(section.rawValue)")
  }
}
