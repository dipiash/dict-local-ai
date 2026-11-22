import Foundation

public enum DiagnosticSanitizer {
  public static func scrub(_ message: String) -> String {
    var text = message.replacingOccurrences(
      of: "[\\r\\n]+", with: " ", options: .regularExpression)
    let patterns: [(String, String)] = [
      (#"(?i)\b(?:authorization|password|secret|token|api_key)=\S+"#, "credential=[redacted]"),
      (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[redacted-email]"),
      (#"(?i)\b(?:file|https?)://\S+"#, "[redacted-url]"),
      (#"(?:/Users/|/Volumes/|/private/|/home/)[^\r\n]+"#, "[redacted-path]"),
    ]
    for (pattern, replacement) in patterns {
      text = text.replacingOccurrences(
        of: pattern, with: replacement, options: .regularExpression)
    }
    return String(text.prefix(2048))
  }
}
