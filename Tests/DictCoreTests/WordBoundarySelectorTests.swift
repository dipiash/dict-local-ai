import XCTest

@testable import DictCore

final class WordBoundarySelectorTests: XCTestCase {
  func testWholeWordAssignedToEarlierWindow() {
    var selector = WordBoundarySelector()
    let first = selector.select(
      tokens: [
        .init(time: 7.8, piece: " transa"),
        .init(time: 8.1, piece: "ction"),
        .init(time: 8.6, piece: " begins"),
      ], start: 0, end: 8, hasRightContext: true)
    XCTAssertEqual(first.tokens.map(\.piece), [" transa", "ction"])
    XCTAssertEqual(first.end, 8.6)
    let second = selector.select(
      tokens: [
        .init(time: 8.1, piece: "ction"),
        .init(time: 8.6, piece: " begins"),
        .init(time: 9.3, piece: " now"),
      ], start: 8, end: 16, hasRightContext: false)
    XCTAssertEqual(second.tokens.map(\.piece), [" begins", " now"])
    XCTAssertEqual(second.start, 8.6)
  }
  func testNoShiftIfNoNewWordWithinOneSecond() {
    var selector = WordBoundarySelector()
    let first = selector.select(
      tokens: [
        .init(time: 7.9, piece: " end"),
        .init(time: 9.5, piece: " late"),
      ], start: 0, end: 8, hasRightContext: true)
    XCTAssertEqual(first.end, 8)
    XCTAssertEqual(first.tokens.map(\.piece), [" end"])
  }
  func testNoDuplicateAtExactBoundary() {
    var selector = WordBoundarySelector()
    _ = selector.select(
      tokens: [.init(time: 8, piece: " next")],
      start: 0, end: 8, hasRightContext: true)
    let second = selector.select(
      tokens: [.init(time: 8, piece: " next")],
      start: 8, end: 16, hasRightContext: false)
    XCTAssertEqual(second.tokens.count, 1)
  }
}
