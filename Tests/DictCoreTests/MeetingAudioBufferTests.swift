import XCTest

@testable import DictCore

final class MeetingAudioBufferTests: XCTestCase {
  func testThreeHoursDrainWithBoundedMemoryAndAbsoluteTimeline() throws {
    var buffer = MeetingAudioBuffer()
    var processed = 0.0
    for second in 0..<10_800 {
      try buffer.append([Float](repeating: 0.1, count: 16_000), at: Double(second))
      while let batch = buffer.take(final: false) {
        XCTAssertEqual(
          batch.offset + Double(batch.window.keep.lowerBound) / 16_000, processed, accuracy: 0.001)
        processed = batch.offset + Double(batch.window.keep.upperBound) / 16_000
      }
      XCTAssertLessThan(buffer.count, 400_000)
    }
    while let batch = buffer.take(final: true) {
      processed = batch.offset + Double(batch.window.keep.upperBound) / 16_000
    }
    XCTAssertEqual(processed, 10_800, accuracy: 0.001)
  }
  func testLateStartAndGapKeepOriginalOffsets() throws {
    var buffer = MeetingAudioBuffer()
    try buffer.append([Float](repeating: 1, count: 16_000), at: 50)
    try buffer.append([Float](repeating: 2, count: 16_000), at: 53)
    let batch = try XCTUnwrap(buffer.take(final: true))
    XCTAssertEqual(
      batch.offset + Double(batch.window.keep.upperBound) / 16_000, 54, accuracy: 0.001)
    XCTAssertTrue(batch.samples.contains(0))
  }
  func testBacklogFailsInsteadOfGrowingOrSilentlyDropping() throws {
    var buffer = MeetingAudioBuffer()
    try buffer.append([Float](repeating: 0, count: MeetingAudioBuffer.capacity), at: 0)
    XCTAssertThrowsError(try buffer.append([1], at: 120))
    XCTAssertEqual(buffer.count, MeetingAudioBuffer.capacity)
  }
}
