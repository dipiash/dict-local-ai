import AppKit
import DictCore
import Foundation

struct AppFailure: LocalizedError {
  let key: String
  private let arguments: [String]

  init(_ key: String, _ arguments: String...) {
    self.key = key
    self.arguments = arguments
  }

  var errorDescription: String? { L10n.format(key, arguments) }
}

enum Paths {
  static var root: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Dict Local AI", isDirectory: true)
  }
  /// History database, audio and preferences. Models stay in `root` even when DICT_DATA_DIR is set.
  static var data: URL { data(environment: ProcessInfo.processInfo.environment) }
  static func data(environment: [String: String]) -> URL {
    ApplicationDataLocation.override(environment: environment) ?? root
  }
  static func prepare() throws { try create(data) }
  static func prepareModels() throws { try create(root) }
  private static func create(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
  }
}
