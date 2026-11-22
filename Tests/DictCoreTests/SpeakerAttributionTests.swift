import XCTest

@testable import DictCore

final class SpeakerAttributionTests: XCTestCase {
  func testReturningSpeakerKeepsNumberAndChangesSplitText() {
    var mapper = SpeakerAttribution()
    let turns = [SpeakerTurn(id: "a", start: 0, end: 4), SpeakerTurn(id: "b", start: 4, end: 8)]
    let first = mapper.segments(
      tokens: [.init(time: 1, piece: " Привет"), .init(time: 5, piece: " Да")],
      turns: turns, start: 0, end: 8)
    XCTAssertEqual(first.map(\.speakerID), ["1", "2"])
    XCTAssertEqual(first.map(\.text), ["Привет", "Да"])
    XCTAssertEqual(first.map(\.end), [5, 8])
    let returning = mapper.segments(
      tokens: [.init(time: 17, piece: " Снова")],
      turns: [.init(id: "a", start: 16, end: 24)], start: 16, end: 24)
    XCTAssertEqual(returning.first?.speakerID, "1")
  }
  func testOverlapAndMissingTurnRemainUnassigned() {
    var mapper = SpeakerAttribution()
    let segments = mapper.segments(
      tokens: [.init(time: 1, piece: " Оба"), .init(time: 5, piece: " Неясно")],
      turns: [.init(id: "a", start: 0, end: 3), .init(id: "b", start: 0, end: 3)], start: 0, end: 8)
    XCTAssertNil(segments.first?.speakerID)
    XCTAssertEqual(segments.first?.text, "Оба Неясно")
  }
  func testSubwordPiecesStayTogetherAndSeparateFilesResetIDs() {
    var mapper = SpeakerAttribution()
    let segments = mapper.segments(
      tokens: [
        .init(time: 1, piece: " разработ"), .init(time: 4, piece: "чик"),
        .init(time: 5, piece: " ответил"),
      ],
      turns: [.init(id: "a", start: 0, end: 3), .init(id: "b", start: 3, end: 8)], start: 0, end: 8)
    XCTAssertEqual(segments.map(\.text), ["разработчик", "ответил"])
    var otherFile = SpeakerAttribution()
    XCTAssertEqual(
      otherFile.segments(
        tokens: [.init(time: 1, piece: " Да")],
        turns: [.init(id: "b", start: 0, end: 8)], start: 0, end: 8
      ).first?.speakerID, "1")
  }
  func testNameSuggestionRequiresConfirmationAndSurvivesJSON() throws {
    var transcript = FileTranscript(source: "talk.m4a", duration: 30)
    transcript.segments = [
      .init(start: 0, end: 8, text: "Меня зовут Иван Петров.", speakerID: "1"),
      .init(start: 8, end: 16, text: "My name is Alice.", speakerID: "2"),
    ]
    transcript.suggestNames()
    XCTAssertEqual(transcript.speakerNameSuggestions["1"], "Иван Петров")
    XCTAssertEqual(transcript.speakerNameSuggestions["2"], "Alice")
    XCTAssertNil(transcript.speakerNames["1"])
    transcript.speakerNames["1"] = "Иван Петров"
    let decoded = try JSONDecoder().decode(FileTranscript.self, from: transcript.json())
    XCTAssertEqual(decoded.speakerNames["1"], "Иван Петров")
    XCTAssertEqual(decoded.segments.first?.speakerID, "1")
    var conflicting = FileTranscript(source: "conflict.m4a", duration: 16)
    conflicting.segments = [
      .init(start: 0, end: 8, text: "Меня зовут Иван. Меня зовут Пётр.", speakerID: "1")
    ]
    conflicting.suggestNames()
    XCTAssertNil(conflicting.speakerNameSuggestions["1"])

  }
}

extension SpeakerAttributionTests {
  func testSpeakerTransitionWithinOneWindowAndReturnAfterUnknown() {
    var mapper = SpeakerAttribution()
    let segments = mapper.segments(
      tokens: [
        .init(time: 1, piece: " Первый"), .init(time: 3, piece: " второй"),
        .init(time: 5, piece: " неясно"), .init(time: 7, piece: " снова первый"),
      ],
      turns: [
        .init(id: "voice-a", start: 0, end: 2), .init(id: "voice-b", start: 2, end: 4),
        .init(id: "voice-a", start: 6, end: 8),
      ], start: 0, end: 8)
    XCTAssertEqual(segments.map(\.speakerID), ["1", "2", nil, "1"])
    XCTAssertEqual(segments.map(\.start), [0, 3, 5, 7])
    XCTAssertEqual(segments.map(\.end), [3, 5, 7, 8])
    let next = mapper.segments(
      tokens: [.init(time: 9, piece: " Второй вернулся")],
      turns: [.init(id: "voice-b", start: 8, end: 16)], start: 8, end: 16)
    XCTAssertEqual(next.first?.speakerID, "2")
  }
}
