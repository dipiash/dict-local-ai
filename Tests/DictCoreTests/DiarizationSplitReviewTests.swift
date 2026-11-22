import XCTest

@testable import DictCore

final class DiarizationSplitReviewTests: XCTestCase {
  private let main = [
    SpeakerTurn(id: "S4", start: 71, end: 84),
    SpeakerTurn(id: "S5", start: 84, end: 101),
  ]
  private func replay(_ start: Double, _ end: Double, single: Bool) -> DiarizationAudit.ChunkRun {
    let turns =
      single
      ? [SpeakerTurn(id: "local-B", start: 70, end: 102)]
      : [
        SpeakerTurn(id: "local-X", start: 70, end: 84),
        SpeakerTurn(id: "local-Y", start: 84, end: 102),
      ]
    return .init(
      windowSeconds: end - start, start: start, end: end,
      turns: turns, distinctSpeakers: single ? 1 : 2, wordCoverage: 0.9)
  }
  func testSyntheticFalseSplitWithOverlappingSecondaryVoice() {
    let transition = 3604.25
    let full = [
      SpeakerTurn(id: "S4", start: 3602.25, end: transition),
      SpeakerTurn(id: "S5", start: transition, end: 3607.6),
      SpeakerTurn(id: "S5", start: 3607.85, end: 3609.2),
      SpeakerTurn(id: "S5", start: 3609.55, end: 3620.4),
    ]
    let replayed = [
      DiarizationAudit.ChunkRun(
        windowSeconds: 180, start: 3580, end: 3760,
        turns: [
          .init(id: "local-A", start: 3602.2, end: 3602.55),
          .init(id: "local-B", start: 3602.4, end: 3609.25),
          .init(id: "local-B", start: 3609.5, end: 3620.5),
        ], distinctSpeakers: 2, wordCoverage: 0.98),
      DiarizationAudit.ChunkRun(
        windowSeconds: 600, start: 3510, end: 4110,
        turns: [
          .init(id: "local-Y", start: 3602.1, end: 3602.6),
          .init(id: "local-X", start: 3602.3, end: 3609.3),
          .init(id: "local-X", start: 3609.5, end: 3620.4),
        ], distinctSpeakers: 2, wordCoverage: 0.98),
    ]
    let result = DiarizationSplitReview.find(main: full, comparisons: replayed)
    XCTAssertTrue(result.contains { $0.beforeSpeaker == "S4" && $0.afterSpeaker == "S5" })
    XCTAssertTrue(result.contains { abs($0.transition - transition) < 0.1 })
  }

  func testTwoIndependentWindowsCatchFalseSplit() {
    let found = DiarizationSplitReview.find(
      main: main, comparisons: [replay(60, 240, single: true), replay(0, 600, single: true)])
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found[0].beforeSpeaker, "S4")
    XCTAssertEqual(found[0].afterSpeaker, "S5")
    XCTAssertEqual(found[0].supportingWindows, 2)
  }
  func testOneReplayIsNotEnough() {
    XCTAssertTrue(
      DiarizationSplitReview.find(
        main: main, comparisons: [replay(60, 240, single: true)]
      ).isEmpty)
  }
  func testReplayThatSeesTwoVoicesDoesNotSuggestMerge() {
    XCTAssertTrue(
      DiarizationSplitReview.find(
        main: main,
        comparisons: [replay(60, 240, single: false), replay(0, 600, single: false)]
      ).isEmpty)
  }
  func testBoundaryWindowHasNoTwoSidedEvidence() {
    XCTAssertTrue(
      DiarizationSplitReview.find(
        main: main,
        comparisons: [replay(84, 240, single: true), replay(0, 600, single: true)]
      ).isEmpty)
  }
  func testEpisodeExtendsAcrossShortFragmentsButStopsAtLongGap() {
    let turns = [
      SpeakerTurn(id: "S4", start: 79, end: 84),
      SpeakerTurn(id: "S5", start: 84, end: 88),
      SpeakerTurn(id: "S5", start: 88.2, end: 93),
      SpeakerTurn(id: "S1", start: 92.8, end: 93.1),
      SpeakerTurn(id: "S5", start: 93.5, end: 101),
      SpeakerTurn(id: "S1", start: 102, end: 105),
      SpeakerTurn(id: "S5", start: 109, end: 110),
    ]
    let candidates = DiarizationSplitReview.find(
      main: turns,
      comparisons: [replay(60, 240, single: true), replay(0, 600, single: true)])
    XCTAssertEqual(candidates.first?.end, 101)
  }

  func testNoGlobalRelabelOnUserConfirmation() {
    let candidate = DiarizationSplitReview.find(
      main: main,
      comparisons: [replay(60, 240, single: true), replay(0, 600, single: true)])[0]
    let segments = [
      TranscriptSegment(start: 84.5, end: 90, text: "question", speakerID: "S5"),
      TranscriptSegment(start: 5100, end: 5104, text: "later", speakerID: "S5"),
      TranscriptSegment(start: 83.5, end: 84.5, text: "crosses boundary", speakerID: "S5"),
    ]
    let corrected = SpeakerReviewEdits.mergeEpisode(segments, candidate: candidate)
    XCTAssertEqual(corrected.changed, 1)
    XCTAssertEqual(corrected.segments[0].speakerID, "S4")
    XCTAssertEqual(corrected.segments[1].speakerID, "S5")
  }
}
