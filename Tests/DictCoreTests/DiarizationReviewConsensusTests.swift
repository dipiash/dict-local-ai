import XCTest

@testable import DictCore

final class DiarizationReviewConsensusTests: XCTestCase {
  private func finding(
    _ start: Double, _ end: Double, windowStart: Double, windowEnd: Double,
    speaker: String = "S2"
  ) -> DiarizationDisagreement.Finding {
    .init(
      start: start, end: end, mainSpeaker: speaker,
      dominantLocalSpeaker: "A", alternateLocalSpeaker: "B",
      dominantSupportSeconds: 80, alternateSupportSeconds: end - start,
      windowStart: windowStart, windowEnd: windowEnd)
  }

  func testGroupsOverlappingWindowsIntoOneCandidate() {
    let input = [
      finding(100, 114, windowStart: 0, windowEnd: 180),
      finding(102, 115, windowStart: 90, windowEnd: 270),
    ]
    let result = DiarizationReviewConsensus.group(input)
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].windowCount, 2)
    XCTAssertEqual(result[0].start, 100)
    XCTAssertEqual(result[0].end, 115)
    XCTAssertEqual(result[0].classification, .repeatedDisagreement)
  }

  func testRepeatedFindingsFromSameWindowDoNotInflateEvidence() {
    let input = [
      finding(100, 114, windowStart: 0, windowEnd: 180),
      finding(103, 115, windowStart: 0, windowEnd: 180),
    ]
    let result = DiarizationReviewConsensus.group(input)
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].windowCount, 1)
    XCTAssertEqual(result[0].classification, .potentialMissedChange)
  }

  func testExistingSecondarySpeakerSplitDoesNotBecomeMissedChangeConsensus() {
    var first = finding(100, 114, windowStart: 0, windowEnd: 180, speaker: "S4")
    first.alreadySeparateSpeaker = true
    var second = finding(102, 115, windowStart: 90, windowEnd: 270, speaker: "S4")
    second.alreadySeparateSpeaker = true
    let result = DiarizationReviewConsensus.group([first, second])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].windowCount, 2)
    XCTAssertEqual(result[0].classification, .existingSpeakerSplit)
  }

  func testDifferentGlobalSpeakersAreNeverMerged() {
    let input = [
      finding(100, 114, windowStart: 0, windowEnd: 180, speaker: "S1"),
      finding(100, 114, windowStart: 90, windowEnd: 270, speaker: "S2"),
    ]
    XCTAssertEqual(DiarizationReviewConsensus.group(input).count, 2)
  }

  func testSeparatedCandidatesRemainDistinct() {
    let input = [
      finding(100, 110, windowStart: 0, windowEnd: 180),
      finding(130, 140, windowStart: 90, windowEnd: 270),
    ]
    XCTAssertEqual(DiarizationReviewConsensus.group(input).count, 2)
  }
}
