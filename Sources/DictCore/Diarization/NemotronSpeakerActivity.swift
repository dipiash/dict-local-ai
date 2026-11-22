import Foundation

public enum NemotronActivityError: Error, Sendable {
  case invalidFrameCount
  case invalidProbabilities
}

public struct NemotronSpeakerActivity: Sendable {
  public let speakerSlots: Int
  public let threshold: Float
  public let minimumTurnSeconds: Double
  public private(set) var frameCount: Int = 0
  private var openFrames: [Int?]
  private var completed: [SpeakerTurn] = []

  public init(speakerSlots: Int = 8, threshold: Float = 0.5, minimumTurnSeconds: Double = 0.12) {
    precondition(speakerSlots > 0)
    self.speakerSlots = speakerSlots
    self.threshold = threshold
    self.minimumTurnSeconds = minimumTurnSeconds
    openFrames = Array(repeating: nil, count: speakerSlots)
  }

  public mutating func append(probabilities: [Float], frames: Int) throws {
    guard frames >= 0, frames <= (Int.max - frameCount),
      frames <= Int.max / speakerSlots, probabilities.count == frames * speakerSlots
    else { throw NemotronActivityError.invalidFrameCount }
    guard probabilities.allSatisfy(\.isFinite) else {
      throw NemotronActivityError.invalidProbabilities
    }
    for frame in 0..<frames {
      let absolute = frameCount + frame
      for slot in 0..<speakerSlots {
        let active = probabilities[frame * speakerSlots + slot] > threshold
        if active {
          if openFrames[slot] == nil { openFrames[slot] = absolute }
        } else if let start = openFrames[slot] {
          close(slot: slot, from: start, to: absolute)
          openFrames[slot] = nil
        }
      }
    }
    frameCount += frames
  }

  public func snapshot() -> [SpeakerTurn] {
    var output = completed
    for (slot, start) in openFrames.enumerated() {
      guard let start, Double(frameCount - start) * 0.01 >= minimumTurnSeconds else { continue }
      output.append(
        SpeakerTurn(
          id: "S\(slot + 1)", start: Double(start) * 0.01,
          end: Double(frameCount) * 0.01))
    }
    return output.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
  }

  public mutating func finish() {
    for (slot, start) in openFrames.enumerated() {
      if let start { close(slot: slot, from: start, to: frameCount) }
      openFrames[slot] = nil
    }
  }

  private mutating func close(slot: Int, from start: Int, to end: Int) {
    guard Double(end - start) * 0.01 >= minimumTurnSeconds else { return }
    completed.append(
      SpeakerTurn(
        id: "S\(slot + 1)", start: Double(start) * 0.01,
        end: Double(end) * 0.01))
  }
}
