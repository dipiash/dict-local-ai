import Foundation

public enum DiagnosticLogDirectory {
  public static func resolve(libraryDirectory: URL, overridePath: String?) -> URL {
    if let overridePath, !overridePath.isEmpty {
      return URL(fileURLWithPath: overridePath, isDirectory: true).standardizedFileURL
    }
    return
      libraryDirectory
      .appendingPathComponent("Logs", isDirectory: true)
      .appendingPathComponent("Dict Local AI", isDirectory: true)
  }

  /// Resolve the active log directory from the user Library or DICT_LOG_DIR.
  public static func activeDirectory(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL {
    let library =
      fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library", isDirectory: true)
    return resolve(libraryDirectory: library, overridePath: environment["DICT_LOG_DIR"])
  }
}
