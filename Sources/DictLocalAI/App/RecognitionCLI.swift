import Darwin
import DictApplication
import DictCore
import Foundation

// Run recognition measurements through the development CLI.
enum RecognitionMode: String, Equatable, CaseIterable {
  case file, meeting
}

struct RecognitionOptions: Equatable {
  let input: String
  let mode: RecognitionMode
  let output: String
}

enum RecognitionCommand: Equatable {
  case help
  case run(RecognitionOptions)
  case invalid(String)
}

enum RecognitionArguments {
  static let flag = "--recognize-audio"
  static let usage = """
    Usage: DictLocalAI --recognize-audio <audio-file> --recognition-mode file|meeting --report-json <json-file>
           DictLocalAI --recognize-audio --help

    Runs the same recognition code as the app without windows and writes one JSON file.
    Exit codes: 0 success, 1 processing error, 2 wrong arguments.
    """

  // Leave normal launches to AppKit when the command flag is absent.
  static func parse(_ arguments: [String]) -> RecognitionCommand? {
    guard let index = arguments.firstIndex(of: flag) else { return nil }
    var rest = Array(arguments[(index + 1)...])
    if rest.contains("--help") { return .help }
    var input: String?
    var mode: String?
    var output: String?
    while !rest.isEmpty {
      let item = rest.removeFirst()
      switch item {
      case "--recognition-mode", "--report-json":
        guard let value = rest.first, !value.hasPrefix("--") else {
          return .invalid("Missing value for \(item).")
        }
        rest.removeFirst()
        if item == "--recognition-mode" { mode = value } else { output = value }
      default:
        if item.hasPrefix("--") { return .invalid("Unknown option \(item).") }
        guard input == nil else { return .invalid("Only one input file is allowed.") }
        input = item
      }
    }
    guard let input else { return .invalid("The audio file is missing.") }
    guard let mode else { return .invalid("--recognition-mode is required (file or meeting).") }
    guard let parsedMode = RecognitionMode(rawValue: mode) else {
      return .invalid("Unknown mode \(mode). Use file or meeting.")
    }
    guard let output else { return .invalid("--report-json is required.") }
    return .run(RecognitionOptions(input: input, mode: parsedMode, output: output))
  }
}

enum RecognitionTimingValue: Encodable, Equatable {
  case seconds(Double)
  case notInstrumented

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .seconds(let value): try container.encode(value)
    case .notInstrumented: try container.encode("not_instrumented")
    }
  }
}

struct RecognitionReport: Encodable {
  struct Input: Encodable {
    var path: String
    var duration: Double?
  }
  struct Model: Encodable {
    var name: String
    var repository: String
    var revision: String?
    var preset: String?
  }
  struct Hardware: Encodable {
    var model: String
    var macos: String
    var ramBytes: UInt64
  }
  struct Segment: Encodable {
    var start: Double
    var end: Double
    var speaker: String?
    var text: String
  }
  struct Word: Encodable {
    var text: String
    var start: Double
    var end: Double
    var speaker: String?
  }

  var runId = UUID().uuidString
  var codeSha = ProcessInfo.processInfo.environment["DICT_CODE_SHA"] ?? "unknown"
  var codeDirty: Bool? = ProcessInfo.processInfo.environment["DICT_CODE_DIRTY"].map { $0 == "1" }
  var mode: String
  var input: Input
  var models: [String: Model] = [:]
  var hardware = RecognitionHardware.current()
  var segments: [Segment] = []
  var words: [Word] = []
  var timings: [String: RecognitionTimingValue] = [:]
  var errors: [String] = []

  func data() throws -> Data {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }
}

enum RecognitionHardware {
  static func current() -> RecognitionReport.Hardware {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var buffer = [CChar](repeating: 0, count: max(size, 1))
    sysctlbyname("hw.model", &buffer, &size, nil, 0)
    return RecognitionReport.Hardware(
      model: String(cString: buffer),
      macos: ProcessInfo.processInfo.operatingSystemVersionString,
      ramBytes: ProcessInfo.processInfo.physicalMemory)
  }
}

struct RecognitionCommandError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

enum RecognitionExitStatus {
  static let success: Int32 = 0
  static let processing: Int32 = 1
  static let arguments: Int32 = 2
}

@MainActor
private final class MeetingTranscriptCollector {
  var final: (segments: [TranscriptSegment], audit: DiarizationAudit)?
  var failure: Error?
}

@MainActor
enum RecognitionCommandRunner {
  static func start(_ command: RecognitionCommand) -> Never {
    switch command {
    case .help:
      print(RecognitionArguments.usage)
      exit(RecognitionExitStatus.success)
    case .invalid(let message):
      FileHandle.standardError.write(Data("\(message)\n\n\(RecognitionArguments.usage)\n".utf8))
      exit(RecognitionExitStatus.arguments)
    case .run(let options):
      // Keep measurement logs out of the app's own log folder; a folder set by the caller wins.
      setenv(
        "DICT_LOG_DIR",
        FileManager.default.temporaryDirectory
          .appendingPathComponent("dict-headless-logs")
          .appendingPathComponent(UUID().uuidString).path,
        0)
      Task { @MainActor in exit(await execute(options)) }
      dispatchMain()
    }
  }

  static func execute(_ options: RecognitionOptions) async -> Int32 {
    let inputURL = URL(fileURLWithPath: options.input).standardizedFileURL
    guard FileManager.default.fileExists(atPath: inputURL.path) else {
      printError("Input file not found: \(inputURL.path)")
      return RecognitionExitStatus.arguments
    }
    var report = RecognitionReport(
      mode: options.mode.rawValue, input: .init(path: inputURL.path, duration: nil))
    let started = ProcessInfo.processInfo.systemUptime
    do {
      // Validate the input file before loading recognition models.
      let duration = try AudioFileReader(url: inputURL).duration
      report.input.duration = duration
      let recognizer = RecognitionService()
      let loadStarted = ProcessInfo.processInfo.systemUptime
      try await loadModels(into: recognizer, report: &report, mode: options.mode)
      report.timings["model_load"] = .seconds(ProcessInfo.processInfo.systemUptime - loadStarted)
      switch options.mode {
      case .file:
        try await transcribeFile(inputURL, with: recognizer, report: &report)
      case .meeting:
        try await transcribeMeeting(inputURL, with: recognizer, report: &report)
      }
      report.timings["total"] = .seconds(ProcessInfo.processInfo.systemUptime - started)
      try write(report, to: options.output)
      return RecognitionExitStatus.success
    } catch {
      let message = L10n.error(error)
      printError(message)
      report.errors.append(message)
      report.timings["total"] = .seconds(ProcessInfo.processInfo.systemUptime - started)
      try? write(report, to: options.output)
      return RecognitionExitStatus.processing
    }
  }

  private static func printError(_ message: String) {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  }

  private static func write(_ report: RecognitionReport, to path: String) throws {
    try report.data().write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  // Restore installed models from their local receipts without fetching files.
  private static func loadModels(
    into recognizer: RecognitionService, report: inout RecognitionReport, mode: RecognitionMode
  ) async throws {
    var loaded: Set<ManagedModel> = []
    var failures: [String] = []
    let setup = ModelSetup(environment: HuggingFaceModelEnvironment(recognizer: recognizer))
    await setup.restore(ManagedModel.allCases) { kind, event in
      switch event {
      case .loaded: loaded.insert(kind)
      case .invalidReceipt: failures.append("\(kind.title): the saved model files did not verify")
      case .failed(let error): failures.append("\(kind.title): \(L10n.error(error))")
      case .checking: break
      }
    }
    for kind in ManagedModel.allCases where !loaded.contains(kind) {
      let detail = failures.first { $0.hasPrefix(kind.title) } ?? "\(kind.title): not installed"
      throw RecognitionCommandError(
        "Model is not ready (\(detail)). Install it in the app settings; this tool never downloads."
      )
    }
    let preset = mode == .file ? "fast128" : "fast32"
    report.models["asr"] = .init(
      name: "parakeet-ultra", repository: ManagedModel.ultra.repository,
      revision: HuggingFaceModels.read(.ultra)?.revision, preset: nil)
    report.models["diarization"] = .init(
      name: "nemotron-3-diarization", repository: ManagedModel.nemotron.repository,
      revision: HuggingFaceModels.read(.nemotron)?.revision, preset: preset)
  }

  private static func transcribeFile(
    _ url: URL, with recognizer: RecognitionService, report: inout RecognitionReport
  ) async throws {
    let stages = StageTimings()
    let began = ProcessInfo.processInfo.systemUptime
    // The same call and the same defaults as FileTranscriptionSession.
    let output = try await recognizer.transcribeFile(
      url, session: RecognitionSession(), identifySpeakers: true, compareChunks: true,
      update: { _, _, _ in },
      stage: { _ in stages.mark() })
    let finished = ProcessInfo.processInfo.systemUptime
    report.timings["recognize_total"] = .seconds(finished - began)
    let marks = stages.values()
    // Stage order in transcribeFile: transcript prepared, speakers search, matching words.
    if marks.count >= 3 {
      report.timings["asr"] = .seconds(marks[0] - began)
      report.timings["diarization"] = .seconds(marks[2] - marks[1])
      // A fourth mark is the first Nemotron replay: replays and what follows get their own key.
      let replaysStart = marks.count > 3 ? marks[3] : finished
      report.timings["alignment_and_review"] = .seconds(replaysStart - marks[2])
      if marks.count > 3 {
        report.timings["voice_review_replays"] = .seconds(finished - replaysStart)
      }
    } else {
      for key in ["asr", "diarization", "alignment_and_review"] {
        report.timings[key] = .notInstrumented
      }
    }
    fill(&report, segments: output.segments, audit: output.audit)
  }

  private static func transcribeMeeting(
    _ url: URL, with recognizer: RecognitionService, report: inout RecognitionReport
  ) async throws {
    let collector = MeetingTranscriptCollector()
    let pipeline = try await recognizer.makePipeline(
      onUpdate: { _, _ in },
      onFailure: { collector.failure = $0 },
      onFinalize: { collector.final = ($0, $1) })
    let session = RecognitionSession()
    let reader = try AudioFileReader(url: url)
    let rate = AudioWindow.sampleRate
    let feedStarted = ProcessInfo.processInfo.systemUptime
    var chunkStart = 0
    feeding: while chunkStart < reader.sampleCount {
      let chunkEnd = min(chunkStart + 60 * rate, reader.sampleCount)
      let chunk = try reader.read(chunkStart..<chunkEnd, session: session)
      var offset = 0
      while offset < chunk.count {
        let blockEnd = min(offset + rate, chunk.count)
        let at = Double(chunkStart + offset) / Double(rate)
        if !pipeline.append(samples: Array(chunk[offset..<blockEnd]), at: at) { break feeding }
        // Wait for the decoder so the 120 s buffer never overflows. Audio time is not slept.
        await pipeline.waitForDrain()
        offset = blockEnd
      }
      chunkStart = chunkEnd
    }
    let finishStarted = ProcessInfo.processInfo.systemUptime
    let result: Result<Void, Error> = await withCheckedContinuation { continuation in
      pipeline.finish { continuation.resume(returning: $0) }
    }
    let finished = ProcessInfo.processInfo.systemUptime
    report.timings["feed_and_decode"] = .seconds(finishStarted - feedStarted)
    report.timings["finish_and_final_alignment"] = .seconds(finished - finishStarted)
    for key in ["asr", "diarization", "alignment_and_review"] {
      report.timings[key] = .notInstrumented
    }
    if case .failure(let error) = result { throw error }
    if let failure = collector.failure { throw failure }
    guard let final = collector.final else {
      throw RecognitionCommandError("The meeting pipeline finished without a final transcript.")
    }
    fill(&report, segments: final.segments, audit: final.audit)
  }

  private static func fill(
    _ report: inout RecognitionReport, segments: [TranscriptSegment], audit: DiarizationAudit?
  ) {
    report.segments = segments.map {
      .init(start: $0.start, end: $0.end, speaker: $0.speakerID, text: $0.text)
    }
    report.words = (audit?.words ?? []).map {
      .init(text: $0.text, start: $0.start, end: $0.end, speaker: $0.assignedSpeaker)
    }
  }
}

@MainActor
private final class StageTimings {
  private var marks: [Double] = []
  func mark() { marks.append(ProcessInfo.processInfo.systemUptime) }
  func values() -> [Double] { marks }
}
