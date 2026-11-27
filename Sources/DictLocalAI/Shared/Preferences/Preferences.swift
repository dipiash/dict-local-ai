import Combine
import Foundation

@MainActor
final class Preferences: ObservableObject {
  @Published var enabled: Bool {
    didSet {
      storage.enabled = enabled
      if oldValue != enabled { UsageTelemetry.action(.settings, .toggleEnabled, value: enabled) }
    }
  }
  @Published var saveHistory: Bool {
    didSet {
      storage.saveHistory = saveHistory
      if oldValue != saveHistory {
        UsageTelemetry.action(.settings, .toggleHistory, value: saveHistory)
      }
    }
  }
  @Published var saveAudio: Bool {
    didSet {
      storage.saveAudio = saveAudio
      if oldValue != saveAudio {
        UsageTelemetry.action(.settings, .toggleHistoryPlayback, value: saveAudio)
      }
    }
  }
  /// Saving audio requires both History and audio retention to be enabled.
  var keepsAudio: Bool { saveHistory && saveAudio }
  @Published var restoreClipboard: Bool {
    didSet {
      storage.restoreClipboard = restoreClipboard
      if oldValue != restoreClipboard {
        UsageTelemetry.action(.settings, .toggleClipboardRestore, value: restoreClipboard)
      }
    }
  }
  @Published var microphone: String {
    didSet {
      storage.microphone = microphone
      if oldValue != microphone {
        UsageTelemetry.action(
          .settings, .selectMicrophone,
          choice: microphone.isEmpty ? "system" : "custom")
      }
    }
  }
  @Published var hold: Shortcut {
    didSet {
      storage.hold = hold
      if oldValue != hold { UsageTelemetry.action(.settings, .setHoldShortcut) }
    }
  }
  @Published var toggle: Shortcut {
    didSet {
      storage.toggle = toggle
      if oldValue != toggle { UsageTelemetry.action(.settings, .setToggleShortcut) }
    }
  }
  private let storage: any PreferencesStorage

  init(storage: any PreferencesStorage) {
    self.storage = storage
    enabled = storage.enabled
    saveHistory = storage.saveHistory
    saveAudio = storage.saveAudio
    restoreClipboard = storage.restoreClipboard
    microphone = storage.microphone
    hold = storage.hold
    toggle = storage.toggle
  }
}
