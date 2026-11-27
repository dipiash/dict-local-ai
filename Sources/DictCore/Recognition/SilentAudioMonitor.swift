import Foundation

/// Measure uninterrupted all-zero system audio to detect a silent capture stream.
public struct SilentAudioMonitor: Sendable {
  public enum Event: Equatable, Sendable {
    case warningRaised(seconds: Int)
    case warningProgress(seconds: Int)
    case resumed(silentSeconds: Int)
  }

  public static let warningSeconds = 120
  private var silenceStart: Double?
  private var silenceEnd = 0.0
  private var warned = false
  private var lastMinute = 0
  public init() {}

  /// Length of the zero run that is still going, for the log when a meeting stops.
  public var ongoingSilenceSeconds: Int {
    guard let start = silenceStart else { return 0 }
    return max(0, Int(silenceEnd - start))
  }

  public mutating func append(_ samples: [Float], at time: Double) -> Event? {
    guard !samples.isEmpty, time.isFinite else { return nil }
    let time = max(0, time)
    if samples.contains(where: { $0 != 0 }) {
      defer { reset() }
      guard warned, let start = silenceStart else { return nil }
      return .resumed(silentSeconds: max(0, Int(time - start)))
    }
    let start = silenceStart ?? time
    silenceStart = start
    silenceEnd = time + Double(samples.count) / Double(AudioWindow.sampleRate)
    let seconds = Int(silenceEnd - start)
    guard seconds >= Self.warningSeconds else { return nil }
    if !warned {
      warned = true
      lastMinute = seconds / 60
      return .warningRaised(seconds: seconds)
    }
    guard seconds / 60 > lastMinute else { return nil }
    lastMinute = seconds / 60
    return .warningProgress(seconds: seconds)
  }

  private mutating func reset() {
    silenceStart = nil
    warned = false
    lastMinute = 0
  }
}

public enum ZeroSampleAudio {
  /// Skip speech recognition only for windows containing exclusively zero-valued samples.
  public static func isSilent(_ samples: [Float]) -> Bool {
    !samples.isEmpty && !samples.contains(where: { $0 != 0 })
  }
}
