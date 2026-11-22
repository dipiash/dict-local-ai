import Foundation

public struct AudioWindow: Equatable, Sendable {
  public let read: Range<Int>
  public let keep: Range<Int>
  public static let sampleRate = 16_000
  public static let frameSamples = 1_280
  public static let chunkSamples = 128_000
  public static let contextSamples = 48_640
  public static let maximumSamples = 30 * 60 * sampleRate

  public static func next(start: Int, available: Int, final: Bool) -> AudioWindow? {
    guard start < available else { return nil }
    let end = min(start + chunkSamples, available)
    if !final && available < end + contextSamples { return nil }
    return AudioWindow(
      read: max(0, start - contextSamples)..<min(available, end + contextSamples),
      keep: start..<end)
  }

  public func owns(frame: Int) -> Bool {
    keep.contains(read.lowerBound + frame * Self.frameSamples)
  }
}

public enum TranscriptCleanup: Sendable {
  public static func apply(_ input: String) -> String {
    let pattern = #"(?i)(?<![\p{L}\p{N}])(?:э(?:[-‑–]?э)+|э[м]+|ммм+)(?![\p{L}\p{N}])[,;:]?\s*"#
    let cleaned = input.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    return cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
