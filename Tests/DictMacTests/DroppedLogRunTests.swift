import XCTest

@testable import DictLocalAI

final class DroppedLogRunTests: XCTestCase {
  func testExclusivelyTheFirstLossOfARunIsReported() {
    var counter = DroppedLogRun()
    XCTAssertTrue(counter.failed())
    XCTAssertFalse(counter.failed())
    XCTAssertFalse(counter.failed())
    XCTAssertEqual(counter.pending, 3)
  }

  func testClearBeginsANewRun() {
    var counter = DroppedLogRun()
    _ = counter.failed()
    counter.clear()
    XCTAssertEqual(counter.pending, 0)
    XCTAssertTrue(counter.failed())
  }
}
