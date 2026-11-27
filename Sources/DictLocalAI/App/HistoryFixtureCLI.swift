import Darwin
import DictCore
import DictStorage
import Foundation

// Seed History fixtures from the CLI only when isolated test data is configured.
struct HistoryFixtureOptions: Equatable {
  let audio: String
  let segments: [String]
}

enum HistoryFixtureCommand: Equatable {
  case run(HistoryFixtureOptions)
  case invalid(String)
}

enum HistoryFixtureArguments {
  static let flag = "--add-history-fixture"

  // Leave normal launches to AppKit when the command flag is absent.
  static func parse(_ arguments: [String]) -> HistoryFixtureCommand? {
    guard let index = arguments.firstIndex(of: flag) else { return nil }
    var rest = Array(arguments[(index + 1)...])
    var audio: String?
    var segments: [String] = []
    while !rest.isEmpty {
      let item = rest.removeFirst()
      if item == "--transcript-line" {
        guard let value = rest.first, !value.hasPrefix("--") else {
          return .invalid("Missing value for --transcript-line.")
        }
        rest.removeFirst()
        segments.append(value)
      } else if item.hasPrefix("--") {
        return .invalid("Unknown option \(item).")
      } else {
        guard audio == nil else { return .invalid("Only one audio file is allowed.") }
        audio = item
      }
    }
    guard let audio else { return .invalid("The audio file is missing.") }
    guard !segments.isEmpty else { return .invalid("At least one --transcript-line is required.") }
    return .run(HistoryFixtureOptions(audio: audio, segments: segments))
  }
}

enum HistoryFixtureRunner {
  static func start(_ command: HistoryFixtureCommand) -> Never {
    switch command {
    case .invalid(let message):
      fail(message, code: 2)
    case .run(let options):
      guard let directory = ApplicationDataLocation.override() else {
        fail("DICT_DATA_DIR is required.", code: 2)
      }
      do {
        try seed(options, into: directory)
        exit(0)
      } catch {
        fail("Seeding failed: \(type(of: error))", code: 1)
      }
    }
  }

  @discardableResult
  static func seed(_ options: HistoryFixtureOptions, into directory: URL) throws -> UUID {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let source = URL(fileURLWithPath: options.audio).standardizedFileURL
    let duration = try AudioFileReader(url: source).duration
    let audioDirectory = HistoryAudioFile.directory(in: directory)
    guard let audio = HistoryAudioFile.copy(from: source, directory: audioDirectory) else {
      throw HistoryFixtureError.audioNotCopied
    }
    // Waits for the copy to finish, so the record never points to a half-written file.
    guard audio.finalizeSynchronously() else { throw HistoryFixtureError.audioNotCopied }
    var transcript = FileTranscript(source: "UI test recording", duration: duration)
    transcript.complete = true
    transcript.processedUntil = duration
    transcript.audioFile = audio.name
    let step = duration / Double(options.segments.count)
    transcript.segments = options.segments.enumerated().map { index, text in
      TranscriptSegment(
        start: Double(index) * step, end: Double(index + 1) * step, text: text,
        speakerID: "S1")
    }
    let store = try RecordingStore(
      url: directory.appendingPathComponent("recordings.sqlite3"), audioDirectory: audioDirectory)
    return try store.create(transcript, category: .file)
  }

  private enum HistoryFixtureError: Error { case audioNotCopied }

  private static func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(code)
  }
}
