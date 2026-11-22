import Foundation

public struct TranscriptSegment: Codable, Equatable, Sendable {
  public let start: Double
  public let end: Double
  public let text: String
  public let speakerID: String?
  public let channel: String?
  public init(
    start: Double, end: Double, text: String, speakerID: String? = nil, channel: String? = nil
  ) {
    self.start = start
    self.end = end
    self.text = text
    self.speakerID = speakerID
    self.channel = channel
  }
}

public struct FileTranscript: Codable, Equatable, Sendable {
  public static let maximumSeconds = 3 * 60 * 60
  public let source: String
  public var duration: Double
  public var startedAt: Date?
  public var processedUntil: Double = 0
  public var complete = false
  // A missing value means the recording did not specify a speaker mode.
  public var speakerRecognitionEnabled: Bool?
  public var diarizationMethod: String?
  public var asrWarnings: [String]?
  public var speakerNames: [String: String] = [:]
  public var speakerNameSuggestions: [String: String] = [:]
  public var segments: [TranscriptSegment] = []
  public let timestampBasis: String
  public let timestampPrecision: String

  public init(source: String, duration: Double) {
    timestampBasis = "seconds_from_session_start"
    timestampPrecision = "approximate_asr_frames_and_speaker_turns"
    self.source = source
    self.duration = duration
  }
  public static func time(_ seconds: Double) -> String {
    let total = Int(max(0, seconds))
    return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
  }
  public static func segmentTime(_ seconds: Double) -> String {
    let tenths = Int((max(0, seconds) * 10).rounded())
    let whole = tenths / 10
    return String(
      format: "%02d:%02d:%02d.%01d", whole / 3600,
      whole / 60 % 60, whole % 60, tenths % 10)
  }
  public var speakerIDs: [String] {
    Array(Set(segments.compactMap(\.speakerID))).sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }
  @discardableResult
  public mutating func editSegmentText(at index: Int, text: String) -> Bool {
    guard segments.indices.contains(index) else { return false }
    let segment = segments[index]
    segments[index] = TranscriptSegment(
      start: segment.start, end: segment.end, text: text,
      speakerID: segment.speakerID, channel: segment.channel)
    return true
  }

  public mutating func suggestNames() {
    let pattern =
      #"(?i:меня зовут|my name is)\s+([\p{Lu}][\p{L}’\x{27}-]+(?:[ ]+[\p{Lu}][\p{L}’\x{27}-]+){0,2})"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
    for id in speakerIDs {
      let text = segments.filter { $0.speakerID == id }.map(\.text).joined(separator: " ")
      let candidates = Set(
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
          match -> String? in
          guard let range = Range(match.range(at: 1), in: text) else { return nil }
          return String(text[range])
        })
      if candidates.count == 1 { speakerNameSuggestions[id] = candidates.first }
    }
  }
  public func json() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }
}
