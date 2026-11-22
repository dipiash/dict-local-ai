import XCTest

@testable import DictCore

final class NemotronSpeakerActivityTests: XCTestCase {
  func testMaintainsSpeakerAcrossChunks() throws {
    var value = NemotronSpeakerActivity(
      speakerSlots: 2, threshold: 0.5,
      minimumTurnSeconds: 0.02)
    try value.append(probabilities: [0.8, 0, 0.9, 0], frames: 2)
    try value.append(probabilities: [0.9, 0, 0, 0], frames: 2)
    XCTAssertEqual(value.frameCount, 4)
    XCTAssertEqual(value.snapshot().count, 1)
    XCTAssertEqual(value.snapshot()[0].id, "S1")
    XCTAssertEqual(value.snapshot()[0].start, 0, accuracy: 0.00001)
    XCTAssertEqual(value.snapshot()[0].end, 0.03, accuracy: 0.00001)
  }

  func testOverlappingSpeakersProduceTwoTurns() throws {
    var value = NemotronSpeakerActivity(
      speakerSlots: 2,
      minimumTurnSeconds: 0.01)
    try value.append(probabilities: [0.8, 0.8, 0.8, 0.8, 0, 0], frames: 3)
    XCTAssertEqual(Set(value.snapshot().map(\.id)), Set(["S1", "S2"]))
  }

  func testShortNoiseIsDiscarded() throws {
    var value = NemotronSpeakerActivity(speakerSlots: 2)
    try value.append(probabilities: [0.8, 0, 0, 0], frames: 2)
    value.finish()
    XCTAssertTrue(value.snapshot().isEmpty)
  }

  func testFlushesActiveTail() throws {
    var value = NemotronSpeakerActivity(
      speakerSlots: 1,
      minimumTurnSeconds: 0.02)
    try value.append(probabilities: [1, 1, 1], frames: 3)
    XCTAssertEqual(value.snapshot().count, 1)
    value.finish()
    XCTAssertEqual(value.snapshot().count, 1)
    XCTAssertEqual(value.snapshot()[0].end, 0.03, accuracy: 0.00001)
  }

  func testInvalidChunkRejectedWithoutAdvancingFrames() throws {
    var value = NemotronSpeakerActivity(speakerSlots: 2)
    XCTAssertThrowsError(try value.append(probabilities: [1], frames: 1))
    XCTAssertThrowsError(try value.append(probabilities: [.nan, 1], frames: 1))
    XCTAssertEqual(value.frameCount, 0)
  }
}
