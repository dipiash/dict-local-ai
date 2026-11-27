import Foundation

@MainActor
protocol PreferencesStorage: AnyObject {
  var enabled: Bool { get set }
  var saveHistory: Bool { get set }
  var saveAudio: Bool { get set }
  var restoreClipboard: Bool { get set }
  var microphone: String { get set }
  var hold: Shortcut { get set }
  var toggle: Shortcut { get set }
}

@MainActor
final class UserDefaultsPreferences: PreferencesStorage {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [
      "enabled": true, "history": true, "historyAudio": true, "restoreClipboard": true,
    ])
  }

  var enabled: Bool {
    get { defaults.bool(forKey: "enabled") }
    set { defaults.set(newValue, forKey: "enabled") }
  }

  var saveHistory: Bool {
    get { defaults.bool(forKey: "history") }
    set { defaults.set(newValue, forKey: "history") }
  }

  var saveAudio: Bool {
    get { defaults.bool(forKey: "historyAudio") }
    set { defaults.set(newValue, forKey: "historyAudio") }
  }

  var restoreClipboard: Bool {
    get { defaults.bool(forKey: "restoreClipboard") }
    set { defaults.set(newValue, forKey: "restoreClipboard") }
  }

  var microphone: String {
    get { defaults.string(forKey: "microphone") ?? "" }
    set { defaults.set(newValue, forKey: "microphone") }
  }

  var hold: Shortcut {
    get { shortcut("hold") ?? .hold }
    set { store(newValue, key: "hold") }
  }

  var toggle: Shortcut {
    get { shortcut("toggle") ?? .toggle }
    set { store(newValue, key: "toggle") }
  }

  private func shortcut(_ key: String) -> Shortcut? {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
  }

  private func store(_ shortcut: Shortcut, key: String) {
    if let data = try? JSONEncoder().encode(shortcut) { defaults.set(data, forKey: key) }
  }
}
