import AVFoundation
import DictStorage
import XCTest

@testable import DictLocalAI

final class HistoryFixtureCommandTests: XCTestCase {
  func testNormalLaunchBypassesDevelopmentCommand() {
    XCTAssertNil(HistoryFixtureArguments.parse(["--other"]))
  }

  func testFixtureArgumentsIncludeAudioAndTranscriptLines() {
    XCTAssertEqual(
      HistoryFixtureArguments.parse([
        "--add-history-fixture", "a.wav", "--transcript-line", "One", "--transcript-line", "Two",
      ]),
      .run(HistoryFixtureOptions(audio: "a.wav", segments: ["One", "Two"])))
  }

  func testRefusesAbsentParts() {
    XCTAssertEqual(
      HistoryFixtureArguments.parse(["--add-history-fixture", "--transcript-line", "One"]),
      .invalid("The audio file is missing."))
    XCTAssertEqual(
      HistoryFixtureArguments.parse(["--add-history-fixture", "a.wav"]),
      .invalid("At least one --transcript-line is required."))
    XCTAssertEqual(
      HistoryFixtureArguments.parse(["--add-history-fixture", "a.wav", "--bad"]),
      .invalid("Unknown option --bad."))
  }

  func testSeedStoresRecordAndAudioInsideTheFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source.wav")
    let format = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
    do {
      let wav = try AVAudioFile(forWriting: source, settings: format.settings)
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000))
      buffer.frameLength = 32_000
      for index in 0..<32_000 { buffer.floatChannelData![0][index] = 0.25 }
      try wav.write(from: buffer)
    }
    let data = folder.appendingPathComponent("data", isDirectory: true)

    let id = try HistoryFixtureRunner.seed(
      HistoryFixtureOptions(audio: source.path, segments: ["First", "Second"]), into: data)

    let store = try RecordingStore(
      url: data.appendingPathComponent("recordings.sqlite3"),
      audioDirectory: HistoryAudioFile.directory(in: data))
    let transcript = try XCTUnwrap(store.load(id))
    XCTAssertEqual(transcript.segments.map(\.text), ["First", "Second"])
    XCTAssertEqual(transcript.duration, 2, accuracy: 0.01)
    let name = try XCTUnwrap(transcript.audioFile)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: HistoryAudioFile.directory(in: data).appendingPathComponent(name).path))
  }
}
