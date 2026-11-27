import XCTest

@testable import DictCore

final class DictCoreTests: XCTestCase {
  func testThirtyMinutesAreCoveredOnceWithBoundedWindows() {
    var position = 0
    var windows: [AudioWindow] = []
    let count = AudioWindow.maximumSamples
    while let window = AudioWindow.next(start: position, available: count, final: true) {
      XCTAssertEqual(window.keep.lowerBound, position)
      XCTAssertLessThanOrEqual(window.read.count, 240_000)
      XCTAssertTrue(window.read.lowerBound <= window.keep.lowerBound)
      XCTAssertTrue(window.read.upperBound >= window.keep.upperBound)
      XCTAssertEqual(window.read.lowerBound % AudioWindow.frameSamples, 0)
      windows.append(window)
      position = window.keep.upperBound
    }
    XCTAssertEqual(position, count)
    XCTAssertEqual(windows.reduce(0) { $0 + $1.keep.count }, count)
  }
  func testStreamingWaitsForRightContextAndFlushesTail() {
    XCTAssertNil(AudioWindow.next(start: 0, available: 128_000, final: false))
    XCTAssertNotNil(AudioWindow.next(start: 0, available: 176_640, final: false))
    let tail = AudioWindow.next(start: 128_000, available: 128_001, final: true)!
    XCTAssertEqual(tail.keep.count, 1)
    XCTAssertTrue(tail.owns(frame: 38))
    XCTAssertFalse(tail.owns(frame: 37))
    XCTAssertNil(AudioWindow.next(start: 0, available: 0, final: true))
  }
  func testCleanupPreservesNegationsRepetitionAndMixedLanguage() {
    XCTAssertEqual(
      TranscriptCleanup.apply("Э-э, не удалять, не удалять retry в Go."),
      "не удалять, не удалять retry в Go.")
    XCTAssertEqual(
      TranscriptCleanup.apply("Ну, вот um exemplo и sehr um…"), "Ну, вот um exemplo и sehr um…")
    XCTAssertEqual(TranscriptCleanup.apply("эм, проверим PR"), "проверим PR")
  }
}

final class FileTranscriptTests: XCTestCase {
  func testThreeHourCoverageAndModelInputBound() {
    let total = FileTranscript.maximumSeconds * AudioWindow.sampleRate
    var cursor = 0
    var windows = 0
    while let window = AudioWindow.next(start: cursor, available: total, final: true) {
      XCTAssertEqual(window.keep.lowerBound, cursor)
      XCTAssertLessThanOrEqual(window.read.count, 240_000)
      XCTAssertEqual(window.read.lowerBound % AudioWindow.frameSamples, 0)
      cursor = window.keep.upperBound
      windows += 1
    }
    XCTAssertEqual(cursor, 172_800_000)
    XCTAssertEqual(windows, 1350)
  }
  func testExportsPreserveOffsetsGapsAndPartialStatus() throws {
    var transcript = FileTranscript(source: "conference.m4a", duration: 10_800)
    transcript.segments = [
      TranscriptSegment(start: 3608, end: 3616, text: "Не удалять API."),
      TranscriptSegment(start: 3624, end: 3625.125, text: "Да, да."),
    ]
    transcript.processedUntil = 3625.125
    let decoded = try JSONDecoder().decode(FileTranscript.self, from: transcript.json())
    XCTAssertFalse(decoded.complete)
    XCTAssertEqual(decoded.segments, transcript.segments)
    XCTAssertEqual(decoded.processedUntil, 3625.125)
  }
  func testExportExcludesLocalAudioFilename() throws {
    var transcript = FileTranscript(source: "talk.m4a", duration: 5)
    transcript.audioFile = "private-name.m4a"
    let text = String(decoding: try transcript.json(), as: UTF8.self)
    XCTAssertFalse(text.contains("audioFile"))
    XCTAssertFalse(text.contains("private-name"))
    XCTAssertEqual(transcript.audioFile, "private-name.m4a")
  }
  func testFailedDiarizationExportsHonestSpeakerFreeText() throws {
    var transcript = FileTranscript(source: "talk.m4a", duration: 20)
    transcript.processedUntil = 20
    transcript.diarizationMethod = "diarization-failed"
    transcript.speakerRecognitionEnabled = false
    transcript.segments = [
      .init(start: 0, end: 20, text: "Technical talk without assigned speakers.")
    ]
    let restored = try JSONDecoder().decode(FileTranscript.self, from: transcript.json())
    XCTAssertEqual(restored.speakerRecognitionEnabled, false)
    XCTAssertEqual(restored.diarizationMethod, "diarization-failed")
    XCTAssertFalse(restored.complete)
  }
  func testTimeFormattingAcrossHourBoundaries() {
    XCTAssertEqual(FileTranscript.time(10_800), "03:00:00")
    XCTAssertEqual(FileTranscript.time(3599.9), "00:59:59")
  }
}
