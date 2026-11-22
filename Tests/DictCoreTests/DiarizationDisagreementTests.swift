import XCTest

@testable import DictCore

final class DiarizationDisagreementTests: XCTestCase {
  private func t(_ id: String, _ start: Double, _ end: Double) -> SpeakerTurn {
    SpeakerTurn(id: id, start: start, end: end)
  }
  private func w(_ turns: [SpeakerTurn], end: Double = 30) -> DiarizationAudit.ChunkRun {
    DiarizationAudit.ChunkRun(
      windowSeconds: end, start: 0, end: end, turns: turns,
      distinctSpeakers: Set(turns.map(\.id)).count, wordCoverage: 1)
  }
  func testFindsOneMissedSpeakerChangeWithoutChangingGlobalLabels() {
    let main = [t("S2", 0, 30)]
    let pieces = [t("A", 0, 12), t("B", 12, 21), t("A", 21, 30)]
    let result = DiarizationDisagreement.find(main: main, comparisons: [w(pieces)])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].mainSpeaker, "S2")
    XCTAssertEqual(result[0].alternateLocalSpeaker, "B")
    XCTAssertEqual(result[0].start, 12, accuracy: 0.001)
    XCTAssertEqual(result[0].end, 21, accuracy: 0.001)
    XCTAssertEqual(main[0].id, "S2")
  }
  func testNoFlagWhenGlobalAndLocalAgreeDespiteDifferentNames() {
    let main = [t("S1", 0, 12), t("S2", 12, 30)]
    let pieces = [t("X", 0, 12), t("Y", 12, 30)]
    XCTAssertTrue(DiarizationDisagreement.find(main: main, comparisons: [w(pieces)]).isEmpty)
  }
  func testShortSecondarySpeechIsNotStrongEvidence() {
    let main = [t("S2", 0, 30)]
    let pieces = [t("A", 0, 28), t("B", 28, 30)]
    XCTAssertTrue(DiarizationDisagreement.find(main: main, comparisons: [w(pieces)]).isEmpty)
  }
  func testOnlyFlagsLocalPartLabeledAsMainSpeaker() {
    let main = [t("S2", 0, 24), t("S4", 24, 30)]
    let pieces = [t("A", 0, 10), t("B", 10, 18), t("A", 18, 24), t("B", 24, 30)]
    let result = DiarizationDisagreement.find(main: main, comparisons: [w(pieces)])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].start, 10, accuracy: 0.001)
    XCTAssertEqual(result[0].end, 18, accuracy: 0.001)
    XCTAssertFalse(result[0].alreadySeparateSpeaker)
  }
  func testSplitOfExistingSecondarySpeakerIsClassifiedSeparately() {
    let main = [t("S2", 0, 20), t("S4", 20, 30)]
    let pieces = [t("A", 0, 20), t("B", 20, 25), t("C", 25, 30)]
    let result = DiarizationDisagreement.find(main: main, comparisons: [w(pieces)])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].mainSpeaker, "S4")
    XCTAssertTrue(result[0].alreadySeparateSpeaker)
  }
  func testFarApartCandidatesRemainSeparate() {
    let main = [t("S2", 0, 60)]
    let pieces = [
      t("A", 0, 10), t("B", 10, 15), t("A", 15, 35),
      t("B", 40, 47), t("A", 47, 60),
    ]
    let result = DiarizationDisagreement.find(main: main, comparisons: [w(pieces, end: 60)])
    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result[0].start, 10, accuracy: 0.001)
    XCTAssertEqual(result[1].start, 40, accuracy: 0.001)
  }
  func testMergesSmallPausesButRejectsBriefNoise() {
    let main = [t("S2", 0, 50)]
    let pieces = [
      t("A", 0, 10), t("B", 10, 14), t("B", 15.7, 20),
      t("A", 20, 46), t("B", 47, 48), t("A", 48, 50),
    ]
    let result = DiarizationDisagreement.find(main: main, comparisons: [w(pieces, end: 50)])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].start, 10, accuracy: 0.001)
    XCTAssertEqual(result[0].end, 20, accuracy: 0.001)
  }
}
