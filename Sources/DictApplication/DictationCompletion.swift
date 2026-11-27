import DictCore

public enum TextInsertionOutcome: Equatable {
  case inserted
  case pasteRequested
  case unavailable
}

public struct DictationCompletion {
  public enum Delivery: Equatable {
    case inserted, pasteRequested, copied, retained
  }

  public private(set) var transcript: FileTranscript
  public let text: String
  public var audioFile: String? {
    get { transcript.audioFile }
    set { transcript.audioFile = newValue }
  }

  public init?(transcript: FileTranscript?, duration: Double) {
    guard var transcript, !transcript.segments.isEmpty else { return nil }
    transcript.duration = duration
    transcript.complete = true
    transcript.suggestNames()
    self.transcript = transcript
    text = transcript.segments.map(\.text).joined(separator: " ")
  }
}
