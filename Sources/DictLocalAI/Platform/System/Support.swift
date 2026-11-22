import AppKit
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
  static func prepare() throws {
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
  }
}
