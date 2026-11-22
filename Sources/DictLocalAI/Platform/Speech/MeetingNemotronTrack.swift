import DictCore
import FluidAudio
import Foundation

@RecognitionActor
final class MeetingNemotronTrack {
  static let config = Nemotron3Config.fast32
  private let diarizer: Nemotron3Diarizer
  private var activity = NemotronSpeakerActivity()
  private var origin: Double?
  private var receivedSamples = 0
  private var chunkIndex = 0
  private let label: String
  private(set) var observations: [DiarizationAudit.PipelineObservation] = []

  init(models: Nemotron3Models, label: String) {
    diarizer = Nemotron3Diarizer(config: Self.config, models: models)
    self.label = label
  }

  func append(samples: [Float], at start: Double) throws {
    guard start.isFinite, start >= 0 else {
      throw AppFailure("meeting.invalid-audio-channel-timestamp")
    }
    if origin == nil { origin = start }
    guard let origin else { return }
    let expected = origin + Double(receivedSamples) / Double(AudioWindow.sampleRate)
    guard abs(expected - start) <= 0.03 else {
      DiagnosticLog.shared.event(
        "nemotron3-meeting", "timeline_error",
        "track=\(label) expected=\(expected) got=\(start)")
      throw AppFailure("meeting.the-audio-timeline-is-out", "\(label)")
    }
    guard samples.allSatisfy(\.isFinite) else {
      throw AppFailure("meeting.audio-channel-contains-invalid-pcm", "\(label)")
    }
    diarizer.appendAudio(samples)
    receivedSamples += samples.count
    try consume(diarizer.processBufferedAudio())
  }

  func finish() throws {
    try consume(diarizer.finishStream())
    activity.finish()
    DiagnosticLog.shared.event(
      "nemotron3-meeting", "track_complete",
      "track=\(label) inputSamples=\(receivedSamples) frames=\(activity.frameCount)"
        + " turns=\(activity.snapshot().count) chunks=\(chunkIndex)")
  }

  func allTurns() -> [SpeakerTurn] {
    guard let origin else { return [] }
    return activity.snapshot().map {
      SpeakerTurn(id: $0.id, start: $0.start + origin, end: $0.end + origin)
    }
  }

  func turns(in interval: Range<Double>) -> [SpeakerTurn] {
    guard let origin else { return [] }
    return activity.snapshot().compactMap { segment in
      let start = segment.start + origin
      let end = segment.end + origin
      guard end > interval.lowerBound, start < interval.upperBound else { return nil }
      return SpeakerTurn(id: segment.id, start: start, end: end)
    }
  }

  private func consume(_ chunks: [Nemotron3ChunkResult]) throws {
    for chunk in chunks {
      let begin = activity.frameCount
      try activity.append(probabilities: chunk.probabilities, frames: chunk.frameCount)
      var peak: Float = 0
      var active = 0
      for probability in chunk.probabilities {
        peak = max(peak, probability)
        if probability > 0.5 { active += 1 }
      }
      let position = (origin ?? 0) + Double(begin) * 0.01
      observations.append(
        .init(
          start: position, end: position + Double(chunk.frameCount) * 0.01,
          stage: "nemotron3_meeting_chunk",
          metrics: [
            "index": Double(chunkIndex), "frames": Double(chunk.frameCount),
            "speakerSlots": Double(chunk.numSpeakers),
            "activeSlotFrames": Double(active), "peakProbability": Double(peak),
            "activityThreshold": 0.5, "latencySeconds": Self.config.latencySeconds,
          ],
          note: "channel=\(label)"))
      DiagnosticLog.shared.event(
        "nemotron3-meeting", "chunk",
        "track=\(label) index=\(chunkIndex) fromFrame=\(begin)"
          + " frames=\(chunk.frameCount) activeSlotFrames=\(active) peak=\(peak)"
          + " preset=fast32 speakerSlots=\(chunk.numSpeakers) threshold=0.5")
      chunkIndex += 1
    }
  }
}
