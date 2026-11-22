import DictCore
import FluidAudio
import Foundation

@RecognitionActor
final class NemotronFileDiarizer {
  static let method = "nemotron3-fast128"
  static let preset = Nemotron3Config.fast128
  static let threshold: Float = 0.5
  static let minimumTurnSeconds: Float = 0.12
  private let models: Nemotron3Models

  init(models: Nemotron3Models) { self.models = models }

  struct Output {
    let turns: [SpeakerTurn]
    let observations: [DiarizationAudit.PipelineObservation]
    let frameCount: Int
    let seconds: Double
  }

  // Use 16 kHz mono samples and offsets from the start of the source.
  func run(
    source: FileAudioSampleSource, firstSample: Int = 0, sampleCount: Int? = nil,
    session: RecognitionSession, diagnostic: Bool
  ) throws -> Output {
    let count = sampleCount ?? (source.sampleCount - firstSample)
    guard firstSample >= 0, count > 0, firstSample <= source.sampleCount,
      count <= source.sampleCount - firstSample
    else { throw AppFailure("recognition.invalid-range-for-nemotron-3") }
    let config = Self.preset
    let diarizer = Nemotron3Diarizer(config: config, models: models)
    var output: [Float] = []
    output.reserveCapacity((count / 160 + 1) * config.numSpeakers)
    var observations: [DiarizationAudit.PipelineObservation] = []
    let startWall = ProcessInfo.processInfo.systemUptime
    let sampleRate = AudioWindow.sampleRate
    let readSize = 10 * sampleRate
    var cursor = 0
    var frameCursor = 0
    var stepIndex = 0

    func consume(_ chunks: [Nemotron3ChunkResult]) {
      for chunk in chunks {
        let began = frameCursor
        frameCursor += chunk.frameCount
        output.append(contentsOf: chunk.probabilities)
        if diagnostic {
          var active = 0
          var top: Float = 0
          var sum: Double = 0
          let total = chunk.frameCount * config.numSpeakers
          for index in 0..<total {
            let probability = chunk.probabilities[index]
            if probability > Self.threshold { active += 1 }
            top = max(top, probability)
            sum += Double(probability)
          }
          observations.append(
            .init(
              start: Double(began) / 100, end: Double(frameCursor) / 100,
              stage: "nemotron3_chunk",
              metrics: [
                "chunkIndex": Double(stepIndex),
                "frames": Double(chunk.frameCount),
                "speakerSlots": Double(config.numSpeakers),
                "activeSlotFrames": Double(active),
                "meanProbability": total > 0 ? sum / Double(total) : 0,
                "peakProbability": Double(top),
                "threshold": Double(Self.threshold),
                "latencySeconds": config.latencySeconds,
              ]))
        }
        stepIndex += 1
      }
    }

    while cursor < count {
      if session.cancelled { throw CancellationError() }
      let amount = min(readSize, count - cursor)
      var samples = [Float](repeating: 0, count: amount)
      try samples.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        try source.copySamples(into: base, offset: firstSample + cursor, count: amount)
      }
      guard samples.allSatisfy(\.isFinite) else {
        throw AppFailure("recognition.the-audio-contains-invalid-pcm")
      }
      diarizer.appendAudio(samples)
      consume(try diarizer.processBufferedAudio())
      cursor += amount
      if cursor == count || cursor % (60 * sampleRate) < readSize {
        DiagnosticLog.shared.event(
          "nemotron3", "progress",
          "processedSamples=\(cursor)/\(count) frames=\(frameCursor) chunks=\(stepIndex)")
      }
    }
    if session.cancelled { throw CancellationError() }
    consume(try diarizer.finishStream())
    let turns = Nemotron3Diarizer.segments(
      probabilities: output, frameCount: frameCursor,
      numSpeakers: config.numSpeakers,
      threshold: Self.threshold, minDurationSeconds: Self.minimumTurnSeconds
    ).map { segment in
      SpeakerTurn(
        id: "S\(segment.speakerIndex + 1)",
        start: Double(segment.startSeconds), end: Double(segment.endSeconds))
    }
    let seconds = ProcessInfo.processInfo.systemUptime - startWall
    DiagnosticLog.shared.event(
      "nemotron3", "run_complete",
      "startSample=\(firstSample) samples=\(count) frames=\(frameCursor)"
        + " turns=\(turns.count) speakers=\(Set(turns.map(\.id)).count)"
        + " profile=fast128 threshold=\(Self.threshold) seconds=\(seconds)")
    observations.append(
      .init(
        start: 0, end: Double(count) / Double(sampleRate), stage: "nemotron3_run",
        metrics: [
          "frames": Double(frameCursor), "chunks": Double(stepIndex),
          "turns": Double(turns.count), "speakers": Double(Set(turns.map(\.id)).count),
          "wallSeconds": seconds,
          "latencySeconds": config.latencySeconds,
          "minimumTurnSeconds": Double(Self.minimumTurnSeconds),
        ], note: "Output frame duration is 0.01s; slot labels are local to this run"))
    return Output(
      turns: turns, observations: observations, frameCount: frameCursor, seconds: seconds)
  }
}
