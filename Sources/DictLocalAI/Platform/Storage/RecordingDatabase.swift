import DictStorage
import Foundation

enum RecordingDatabase {
  static let shared: Result<RecordingStore, Error> = Result {
    do {
      try Paths.prepare()
      return try RecordingStore(
        url: Paths.root.appendingPathComponent("recordings.sqlite3"),
        onEvent: { event, details in
          DiagnosticLog.shared.event("history-db", event, details)
        })
    } catch {
      DiagnosticLog.shared.event(
        "history-db", "initialization_failed", "error_type=\(type(of: error))")
      throw error
    }
  }

  static func require() throws -> RecordingStore { try shared.get() }
}
