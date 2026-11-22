import Foundation

public enum DictationPhase: Equatable, Sendable {
  case idle, recording, processing, interrupted, failed, result
  public var canStart: Bool { self == .idle || self == .result }
  public var hasAudio: Bool {
    self == .recording || self == .processing || self == .interrupted || self == .failed
  }
}
