import Foundation

// This report contains transcript words. Export it only on request.
public struct DiarizationAudit: Codable, Sendable {
  public struct Word: Codable, Sendable {
    public let text: String
    public let start: Double
    public let end: Double
    public let rawSpeaker: String?
    public let assignedSpeaker: String?
    public let supportSeconds: Double
    public let confidence: Double
    public let reason: String

    public init(
      text: String, start: Double, end: Double, rawSpeaker: String?, assignedSpeaker: String?,
      supportSeconds: Double, confidence: Double, reason: String
    ) {
      self.text = text
      self.start = start
      self.end = end
      self.rawSpeaker = rawSpeaker
      self.assignedSpeaker = assignedSpeaker
      self.supportSeconds = supportSeconds
      self.confidence = confidence
      self.reason = reason
    }
  }

  public struct ChunkRun: Codable, Sendable {
    public let windowSeconds: Double
    public let clusteringThreshold: Double
    public let start: Double
    public let end: Double
    public let turns: [SpeakerTurn]
    // A speaker ID is only valid in its own replay window.
    public let distinctSpeakers: Int
    public let wordCoverage: Double

    public init(
      windowSeconds: Double, start: Double, end: Double, turns: [SpeakerTurn],
      distinctSpeakers: Int, wordCoverage: Double, clusteringThreshold: Double = 0.6
    ) {
      self.windowSeconds = windowSeconds
      self.clusteringThreshold = clusteringThreshold
      self.start = start
      self.end = end
      self.turns = turns
      self.distinctSpeakers = distinctSpeakers
      self.wordCoverage = wordCoverage
    }
  }

  public struct PipelineObservation: Codable, Sendable {
    public let start: Double
    public let end: Double
    public let stage: String
    public let metrics: [String: Double]
    public let note: String

    public init(
      start: Double, end: Double, stage: String, metrics: [String: Double], note: String = ""
    ) {
      self.start = start
      self.end = end
      self.stage = stage
      self.metrics = metrics
      self.note = note
    }
  }

  public struct EngineInfo: Codable, Sendable {
    public let name: String
    public let preset: String
    public let modelRepository: String
    public let fluidAudioCommit: String
    public let speakerSlots: Int
    public let outputFrameSeconds: Double
    public let activityThreshold: Double
    public let minimumTurnSeconds: Double

    public init(
      name: String, preset: String, modelRepository: String,
      fluidAudioCommit: String, speakerSlots: Int, outputFrameSeconds: Double,
      activityThreshold: Double, minimumTurnSeconds: Double
    ) {
      self.name = name
      self.preset = preset
      self.modelRepository = modelRepository
      self.fluidAudioCommit = fluidAudioCommit
      self.speakerSlots = speakerSlots
      self.outputFrameSeconds = outputFrameSeconds
      self.activityThreshold = activityThreshold
      self.minimumTurnSeconds = minimumTurnSeconds
    }
  }

  public let engineInfo: EngineInfo?

  public let pipelineObservations: [PipelineObservation]?
  public let schemaVersion: Int
  public let source: String
  public let duration: Double
  public let method: String
  public let words: [Word]
  public let rawTurns: [SpeakerTurn]
  public let chunkRuns: [ChunkRun]
  public let note: String
  public let warnings: [String]

  public init(
    source: String, duration: Double, method: String, words: [Word],
    rawTurns: [SpeakerTurn], chunkRuns: [ChunkRun] = [],
    warnings: [String] = [], pipelineObservations: [PipelineObservation]? = nil,
    engineInfo: EngineInfo? = nil
  ) {
    self.schemaVersion = 3
    self.pipelineObservations = pipelineObservations
    self.engineInfo = engineInfo
    self.source = source
    self.duration = duration
    self.method = method
    self.words = words
    self.rawTurns = rawTurns
    self.chunkRuns = chunkRuns
    self.warnings = warnings
    self.note =
      "Word times are approximate ASR onsets; wordCoverage is not DER. "
      + "Chunk-local speaker IDs are unrelated to full-file IDs. "
      + "Word confidence is temporal support share, not acoustic model confidence. "
      + "Pipeline frame/sample observations can overlap; they are not unique timeline coverage. "
      + "Replay speaker slots are local to each run, and replayed slices have different context. "
      + "Nemotron chunk metrics contain numeric probabilities, not speaker embeddings. "
      + "The JSON contains recognized text: export it only with user consent."
  }

  public var unknownReasons: [String: Int] {
    var counts: [String: Int] = [:]
    for word in words where word.assignedSpeaker == nil {
      counts[word.reason, default: 0] += 1
    }
    return counts
  }

  public var wordCoverage: Double {
    guard !words.isEmpty else { return 0 }
    return Double(words.filter { $0.assignedSpeaker != nil }.count) / Double(words.count)
  }

  public func json() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }
}

public enum DiarizationCoverage {
  public static func wordCoverage(
    tokens: [RecognizedToken], turns: [SpeakerTurn], start: Double, end: Double
  ) -> Double {
    var times: [Double] = []
    var firstToken = true
    for token in tokens {
      let newWord = firstToken || token.piece.first?.isWhitespace == true
      firstToken = false
      if newWord && token.time.isFinite && token.time >= start && token.time < end {
        times.append(token.time)
      }
    }
    guard !times.isEmpty else { return 0 }
    let intervals = turns.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
      .sorted { $0.start < $1.start }
    var covered = 0
    var cursor = 0
    var latestEnd = -Double.infinity
    for time in times.sorted() {
      while cursor < intervals.count && intervals[cursor].start <= time {
        latestEnd = max(latestEnd, intervals[cursor].end)
        cursor += 1
      }
      if latestEnd > time { covered += 1 }
    }
    return Double(covered) / Double(times.count)
  }
}
