import XCTest

@testable import DictCore

final class UnassignedSpeechReviewTests: XCTestCase {
  private func word(_ start: Double, _ end: Double, id: String? = nil) -> DiarizationAudit.Word {
    .init(
      text: "a", start: start, end: end, rawSpeaker: id,
      assignedSpeaker: id, supportSeconds: 0, confidence: 0,
      reason: id == nil ? "no_turn" : "matched")
  }
  func testGroupsMultipleUnknownWords() {
    let spans = UnassignedSpeechReview.find(words: [
      word(1, 2), word(2, 3), word(3, 4), word(9, 10), word(10, 11), word(11, 12),
    ])
    XCTAssertEqual(spans.count, 2)
    XCTAssertEqual(spans[0].words, 3)
    XCTAssertEqual(spans[1].start, 9)
  }
  func testIgnoresSingleWordsAndAssignedWords() {
    XCTAssertTrue(
      UnassignedSpeechReview.find(words: [
        word(1, 1.2), word(3, 3.5, id: "S1"), word(6, 7),
      ]).isEmpty)
  }
}
