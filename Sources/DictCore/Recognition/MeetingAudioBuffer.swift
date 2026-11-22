import Foundation

public enum MeetingBufferError: Error, Sendable { case invalidTime, backlogExceeded, outOfOrder }

public struct MeetingAudioBuffer: Sendable {
  public static let capacity = 120 * AudioWindow.sampleRate
  private var samples: [Float] = []
  private var base = 0
  private var cursor = 0
  private var initialized = false
  public var count: Int { samples.count }
  public init() {}

  public mutating func append(_ input: [Float], at seconds: Double) throws {
    guard seconds.isFinite, seconds >= 0 else {
      throw MeetingBufferError.invalidTime
    }
    guard seconds < 10_800 else { return }
    guard !input.isEmpty else { return }
    let position = Int((seconds * Double(AudioWindow.sampleRate)).rounded())
    if !initialized {
      base = position / AudioWindow.frameSamples * AudioWindow.frameSamples
      initialized = true
    }
    let end = base + samples.count
    // Resampling can round timestamps by a few samples.
    guard position >= end - 160 else { throw MeetingBufferError.outOfOrder }
    let overlap = max(0, end - position)
    let gap = max(0, position - end)
    let accepted = min(input.count, max(0, 10_800 * AudioWindow.sampleRate - position))
    let remaining = max(0, accepted - overlap)
    guard samples.count + gap + remaining <= Self.capacity else {
      throw MeetingBufferError.backlogExceeded
    }
    if gap > 0 { samples.append(contentsOf: repeatElement(Float(0), count: gap)) }
    samples.append(contentsOf: input.prefix(accepted).dropFirst(min(overlap, accepted)))
  }

  public mutating func take(final: Bool) -> (samples: [Float], window: AudioWindow, offset: Double)?
  {
    guard let window = AudioWindow.next(start: cursor, available: samples.count, final: final)
    else { return nil }
    let output = Array(samples[window.read])
    let offset = Double(base) / Double(AudioWindow.sampleRate)
    cursor = window.keep.upperBound
    let discard = max(0, cursor - AudioWindow.contextSamples)
    if discard > 0 {
      samples.removeFirst(discard)
      base += discard
      cursor -= discard
    }
    return (output, window, offset)
  }
}
