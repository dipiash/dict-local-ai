import Foundation

/// Formats of repeated log fields. Only numbers, codes and short ids go in, never text or names.
enum DiagnosticFields {
  /// Seconds rounded to 0.1.
  static func seconds(_ value: Double) -> String { String(format: "%.1f", value) }

  /// Whole milliseconds from seconds.
  static func milliseconds(_ seconds: Double) -> String { String(Int(seconds * 1000)) }

  /// Megabytes of a byte count, rounded to 0.1.
  static func megabytes(_ bytes: Int64) -> String {
    String(format: "%.1f", Double(bytes) / 1_048_576)
  }

  /// The first 8 characters of an audio file name, which is a random UUID.
  static func audioID(_ fileName: String) -> String { String(fileName.prefix(8)) }

  static func error(_ error: Error) -> String {
    let ns = error as NSError
    return "error_type=\(type(of: error)) error_domain=\(ns.domain) error_code=\(ns.code)"
  }
}
