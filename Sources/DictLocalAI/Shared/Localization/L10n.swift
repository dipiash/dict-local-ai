import DictApplication
import DictCore
import Foundation

enum L10n {
  private static let language = Bundle.main.preferredLocalizations.first ?? "en"

  static func text(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
  }

  static func text(_ key: String, _ arguments: CVarArg...) -> String {
    format(key, arguments)
  }

  static func format(_ key: String, _ arguments: [CVarArg]) -> String {
    guard !arguments.isEmpty else { return text(key) }
    return String(format: text(key), locale: Locale(identifier: language), arguments: arguments)
  }

  static func error(_ error: Error) -> String {
    guard let database = error as? RecordingStorageError else {
      return error.localizedDescription
    }
    switch database.kind {
    case .storage: return text("history.database-unavailable")
    case .missingRecord: return text("history.record-missing")
    }
  }
}
