import XCTest

@testable import DictCore

final class OfflineTranscriptAlignerTests: XCTestCase {
  func testMonologueAcrossASRWindowsIsOneSpeaker() {
    let tokens: [RecognizedToken] = [
      .init(time: 0.2, piece: " You"), .init(time: 0.65, piece: " should"),
      .init(time: 1.0, piece: " tell"), .init(time: 1.32, piece: " a"),
      .init(time: 1.48, piece: " story."), .init(time: 8.1, piece: " I"),
      .init(time: 8.32, piece: " don't"), .init(time: 8.69, piece: " care."),
    ]
    let turns = [
      SpeakerTurn(id: "talker", start: 0.1, end: 8.0),
      SpeakerTurn(id: "talker", start: 8.0, end: 9.3),
    ]
    let result = OfflineTranscriptAligner().align(tokens: tokens, turns: turns, duration: 10)
    XCTAssertTrue(result.allSatisfy { $0.speakerID == "1" })
    XCTAssertEqual(
      result.map(\.text).joined(separator: " "),
      "You should tell a story. I don't care.")
  }

  func testRealSpeakerTransitionAndStableReturningSpeaker() {
    let tokens = [
      RecognizedToken(time: 0.2, piece: " One."),
      RecognizedToken(time: 2.2, piece: " Two."),
      RecognizedToken(time: 4.2, piece: " Back."),
    ]
    let turns = [
      SpeakerTurn(id: "a", start: 0, end: 1),
      SpeakerTurn(id: "b", start: 2, end: 3),
      SpeakerTurn(id: "a", start: 4, end: 5),
    ]
    let result = OfflineTranscriptAligner().align(tokens: tokens, turns: turns, duration: 6)
    XCTAssertEqual(result.map(\.speakerID), ["1", "2", "1"])
  }

  func testNoSpeakerModeDoesNotInventSpeakersOrChangeWords() {
    let result = OfflineTranscriptAligner().align(
      tokens: [
        .init(time: 0, piece: " hello"), .init(time: 0.4, piece: "world"),
        .init(time: 1, piece: " next"),
      ], turns: [], duration: 2, useSpeakers: false)
    XCTAssertEqual(result.map(\.text), ["helloworld next"])
    XCTAssertTrue(result.allSatisfy { $0.speakerID == nil })
  }

  func testOverlappingSpeakersRemainUnknownRatherThanRandomlyAssigned() {
    let result = OfflineTranscriptAligner().align(
      tokens: [.init(time: 1.0, piece: " Both")],
      turns: [
        SpeakerTurn(id: "a", start: 0, end: 3),
        SpeakerTurn(id: "b", start: 0, end: 3),
      ], duration: 3)
    XCTAssertNil(result.first?.speakerID)
  }

  func testInvalidIntervalsIgnored() {
    let segments = OfflineTranscriptAligner().align(
      tokens: [.init(time: 1, piece: " Test")],
      turns: [
        .init(id: "a", start: .nan, end: 4),
        .init(id: "b", start: 0, end: .infinity),
      ], duration: 4)
    XCTAssertNil(segments.first?.speakerID)
  }

  func testShortSpeakerChangeWithStrongEvidenceIsPreserved() {
    let result = OfflineTranscriptAligner().align(
      tokens: [
        .init(time: 0.5, piece: " Main."),
        .init(time: 2.3, piece: " Yes."),
        .init(time: 3.5, piece: " Main."),
      ],
      turns: [
        .init(id: "a", start: 0, end: 2),
        .init(id: "b", start: 2.1, end: 3.1),
        .init(id: "a", start: 3.3, end: 4.5),
      ], duration: 5)
    XCTAssertEqual(result.map(\.speakerID), ["1", "2", "1"])
  }
}
