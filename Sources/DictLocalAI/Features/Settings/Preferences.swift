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
    microphone = storage.microphone
    hold = storage.hold
    toggle = storage.toggle
  }
}
