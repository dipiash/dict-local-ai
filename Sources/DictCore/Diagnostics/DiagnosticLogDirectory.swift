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
}
