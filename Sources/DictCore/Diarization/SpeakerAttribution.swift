import Foundation

public struct RecognizedToken: Codable, Sendable {
  public let time: Double
  public let piece: String
  public init(time: Double, piece: String) {
    self.time = time
    self.piece = piece
  }
}

public struct SpeakerTurn: Codable, Sendable {
  public let id: String
  public let start: Double
  public let end: Double
  public init(id: String, start: Double, end: Double) {
    self.id = id
    self.start = start
    self.end = end
  }
}

public struct SpeakerAttribution: Sendable {
  private var numbers: [String: String] = [:]
  private let preserveRawIDs: Bool
  public init(preserveRawIDs: Bool = false) { self.preserveRawIDs = preserveRawIDs }

  public mutating func segments(
    tokens: [RecognizedToken], turns: [SpeakerTurn],
    start: Double, end: Double
  ) -> [TranscriptSegment] {
    var result: [TranscriptSegment] = []
    var speaker: String?
    var text = ""
    var began = start
    func label(at time: Double) -> String? {
      let ids = Set(turns.filter { $0.start <= time && time < $0.end }.map(\.id))
      return ids.count == 1 ? ids.first : nil
    }
    func append(until time: Double) {
      let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !content.isEmpty {
        result.append(
          TranscriptSegment(start: began, end: max(began, time), text: content, speakerID: speaker))
      }
    }
    for token in tokens {
      let time = min(end, max(start, token.time))
      let newWord = text.isEmpty || token.piece.first?.isWhitespace == true
      if newWord {
        let rawID = label(at: time)
        let next: String?
        if let rawID {
          if preserveRawIDs {
            next = rawID
          } else {
            if numbers[rawID] == nil { numbers[rawID] = String(numbers.count + 1) }
            next = numbers[rawID]
          }
        } else {
          next = nil
        }
        if !text.isEmpty && next != speaker {
          append(until: time)
          text = ""
          began = time
        }
        speaker = next
      }
      text += token.piece
    }
    append(until: end)
    return result
  }
}
