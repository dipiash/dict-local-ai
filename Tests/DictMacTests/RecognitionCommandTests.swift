import XCTest

@testable import DictLocalAI

@MainActor
final class RecognitionCommandTests: XCTestCase {
  private let flag = RecognitionArguments.flag

  func testNormalLaunchBypassesDevelopmentCommand() {
    XCTAssertNil(RecognitionArguments.parse([]))
    XCTAssertNil(RecognitionArguments.parse(["--check-localization"]))
    XCTAssertNil(RecognitionArguments.parse(["--help"]))
  }

  func testHelpIsAccepted() {
    XCTAssertEqual(RecognitionArguments.parse([flag, "--help"]), .help)
  }

  func testRecognitionArgumentsAcceptFileAndMeetingModes() {
    for mode in RecognitionMode.allCases {
      let command = RecognitionArguments.parse(
        [flag, "a.m4a", "--recognition-mode", mode.rawValue, "--report-json", "out.json"])
      XCTAssertEqual(
        command, .run(RecognitionOptions(input: "a.m4a", mode: mode, output: "out.json")))
    }
  }

  func testRecognitionOptionsAcceptedBeforeAudioPath() {
    let command = RecognitionArguments.parse(
      [flag, "--report-json", "o.json", "--recognition-mode", "file", "a.m4a"])
    XCTAssertEqual(
      command, .run(RecognitionOptions(input: "a.m4a", mode: .file, output: "o.json")))
  }

  func testRefusesBadArguments() {
    let bad: [[String]] = [
      [flag],
      [flag, "--recognition-mode", "file", "--report-json", "o.json"],
      [flag, "a.m4a", "--recognition-mode", "live", "--report-json", "o.json"],
      [flag, "a.m4a", "--report-json", "o.json"],
      [flag, "a.m4a", "--recognition-mode", "file"],
      [flag, "a.m4a", "b.m4a", "--recognition-mode", "file", "--report-json", "o.json"],
      [flag, "a.m4a", "--recognition-mode", "--report-json", "o.json"],
      [flag, "a.m4a", "--recognition-mode", "file", "--report-json", "o.json", "--extra"],
    ]
    for arguments in bad {
      guard case .invalid = RecognitionArguments.parse(arguments) else {
        return XCTFail("Expected invalid for \(arguments)")
      }
    }
  }

  func testReportReadsSnakeCaseKeysAndMarksAbsentTimings() throws {
    var report = RecognitionReport(mode: "file", input: .init(path: "/a.m4a", duration: 1.5))
    report.timings = ["asr": .seconds(2), "diarization": .notInstrumented]
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: report.data()) as? [String: Any])
    XCTAssertNotNil(object["run_id"])
    XCTAssertNotNil(object["code_sha"])
    let timings = try XCTUnwrap(object["timings"] as? [String: Any])
    XCTAssertEqual(timings["asr"] as? Double, 2)
    XCTAssertEqual(timings["diarization"] as? String, "not_instrumented")
  }

  private func run(_ prepare: (URL) throws -> URL) async throws -> (Int32, [String: Any]?) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = try prepare(folder)
    let output = folder.appendingPathComponent("out.json")
    let code = await RecognitionCommandRunner.execute(
      RecognitionOptions(input: input.path, mode: .file, output: output.path))
    let json = (try? Data(contentsOf: output)).flatMap {
      try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
    }
    return (code, json)
  }

  func testAbsentFileIsAnArgumentFailure() async throws {
    let (code, json) = try await run { $0.appendingPathComponent("missing.m4a") }
    XCTAssertEqual(code, RecognitionExitStatus.arguments)
    XCTAssertNil(json)
  }

  func testBlankFileFailsWithProcessingFailure() async throws {
    let (code, json) = try await run {
      let url = $0.appendingPathComponent("empty.m4a")
      try Data().write(to: url)
      return url
    }
    XCTAssertEqual(code, RecognitionExitStatus.processing)
    XCTAssertFalse(((json?["errors"] as? [String]) ?? []).isEmpty)
  }

  func testBrokenFileFailsWithProcessingFailure() async throws {
    let (code, json) = try await run {
      let url = $0.appendingPathComponent("broken.m4a")
      try Data("not audio at all".utf8).write(to: url)
      return url
    }
    XCTAssertEqual(code, RecognitionExitStatus.processing)
    XCTAssertFalse(((json?["errors"] as? [String]) ?? []).isEmpty)
  }
}
