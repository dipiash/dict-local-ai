import Foundation

public enum ApplicationDataLocation {
  public static func override(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL? {
    guard let path = environment["DICT_DATA_DIR"], !path.isEmpty else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
  }

  public static func resolve(applicationSupport: URL, overridePath: String?) -> URL {
    if let overridePath, !overridePath.isEmpty {
      return URL(fileURLWithPath: overridePath, isDirectory: true).standardizedFileURL
    }
    return applicationSupport.appendingPathComponent("Dict Local AI", isDirectory: true)
  }
}
