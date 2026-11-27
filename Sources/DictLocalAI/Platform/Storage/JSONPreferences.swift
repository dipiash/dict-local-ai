import DictCore
import Foundation

/// Settings kept in a JSON file inside DICT_DATA_DIR, so UI tests never touch the user's settings.
@MainActor
final class JSONPreferences: PreferencesStorage {
  private struct Values: Codable {
    var enabled: Bool?
    var history: Bool?
    var historyAudio: Bool?
    var restoreClipboard: Bool?
    var microphone: String?
    var hold: Shortcut?
    var toggle: Shortcut?
  }

  private let file: URL
  private var values: Values

  init(directory: URL) {
    file = directory.appendingPathComponent("preferences.json")
    values =
      (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Values.self, from: $0) }
      ?? Values()
  }

  var enabled: Bool {
    get { values.enabled ?? true }
    set { update { $0.enabled = newValue } }
  }

  var saveHistory: Bool {
    get { values.history ?? true }
    set { update { $0.history = newValue } }
  }

  var saveAudio: Bool {
    get { values.historyAudio ?? true }
    set { update { $0.historyAudio = newValue } }
  }

  var restoreClipboard: Bool {
    get { values.restoreClipboard ?? true }
    set { update { $0.restoreClipboard = newValue } }
  }

  var microphone: String {
    get { values.microphone ?? "" }
    set { update { $0.microphone = newValue } }
  }

  var hold: Shortcut {
    get { values.hold ?? .hold }
    set { update { $0.hold = newValue } }
  }

  var toggle: Shortcut {
    get { values.toggle ?? .toggle }
    set { update { $0.toggle = newValue } }
  }

  private func update(_ change: (inout Values) -> Void) {
    change(&values)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    if let data = try? encoder.encode(values) { try? data.write(to: file, options: .atomic) }
  }
}

@MainActor
enum PreferencesFactory {
  static func make(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> any PreferencesStorage {
    if let directory = ApplicationDataLocation.override(environment: environment) {
      return JSONPreferences(directory: directory)
    }
    return UserDefaultsPreferences()
  }
}
