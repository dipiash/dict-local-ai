import XCTest

@testable import DictCore

final class DiarizationAuditTests: XCTestCase {
  func testUnknownReasonsDistinguishMissingTurnFromAmbiguousOverlap() {
    let tokens = [
      RecognizedToken(time: 0.5, piece: " one"),
      RecognizedToken(time: 1.5, piece: " gap"),
      RecognizedToken(time: 2.5, piece: " both"),
    ]
    let turns = [
      SpeakerTurn(id: "a", start: 0, end: 1),
      SpeakerTurn(id: "a", start: 2.2, end: 3),
      SpeakerTurn(id: "b", start: 2.2, end: 3),
    ]
    let output = OfflineTranscriptAligner().detailedAlignment(
      tokens: tokens, turns: turns, duration: 3)
    XCTAssertEqual(output.words.map(\.reason), ["matched", "no_turn", "ambiguous_overlap"])
    XCTAssertEqual(output.words[0].assignedSpeaker, "a")
    XCTAssertNil(output.words[1].assignedSpeaker)
    XCTAssertNil(output.words[2].assignedSpeaker)
  }

  func testAuditReportsFinalStabilizedReasonAndEncodesRoundTrip() throws {
    let output = OfflineTranscriptAligner().detailedAlignment(
      tokens: [
        .init(time: 0.5, piece: " first"),
        .init(time: 1.5, piece: " bridge"),
        .init(time: 2.5, piece: " last"),
      ],
      turns: [
        .init(id: "a", start: 0.2, end: 1.1),
        .init(id: "a", start: 2.2, end: 3.1),
      ], duration: 3.5)
    XCTAssertEqual(output.words[1].rawSpeaker, nil)
    XCTAssertEqual(output.words[1].assignedSpeaker, "a")
    XCTAssertEqual(output.words[1].reason, "bridged_same_speaker")
    let report = DiarizationAudit(
      source: "fixture.m4a", duration: 3.5, method: "nemotron3-fast128",
      words: output.words,
      rawTurns: [.init(id: "a", start: 0.2, end: 1.1)])
    let decoded = try JSONDecoder().decode(DiarizationAudit.self, from: report.json())
    XCTAssertEqual(decoded.words.count, 3)
    XCTAssertEqual(decoded.words[1].reason, "bridged_same_speaker")
    XCTAssertEqual(decoded.wordCoverage, 1, accuracy: 0.001)
  }

  func testCoverageDoesNotDoubleCountOverlapsAndIgnoresInvalidTurns() {
    let tokens = [
      RecognizedToken(time: 1, piece: " one"),
      RecognizedToken(time: 3, piece: " two"),
      RecognizedToken(time: 5, piece: " three"),
    ]
    let turns = [
      SpeakerTurn(id: "a", start: 0, end: 2),
      SpeakerTurn(id: "b", start: 0, end: 2),
      SpeakerTurn(id: "x", start: .nan, end: 100),
      SpeakerTurn(id: "c", start: 4, end: 6),
    ]
    XCTAssertEqual(
      DiarizationCoverage.wordCoverage(tokens: tokens, turns: turns, start: 0, end: 6),
      2.0 / 3.0, accuracy: 0.001)
  }

}
