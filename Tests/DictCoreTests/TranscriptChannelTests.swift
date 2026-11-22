import XCTest

@testable import DictCore

final class TranscriptChannelTests: XCTestCase {
  func testJSONRoundTripPreservesChannelAndDiarizationMethod() throws {
    var result = FileTranscript(source: "Созвон", duration: 3)
    result.speakerRecognitionEnabled = true
    result.diarizationMethod = "nemotron3-fast32"
    result.segments = [.init(start: 0, end: 1, text: "Hello", speakerID: "1", channel: "system")]
    let decoded = try JSONDecoder().decode(FileTranscript.self, from: result.json())
    XCTAssertEqual(decoded, result)
    XCTAssertEqual(decoded.segments[0].channel, "system")
  }
}
