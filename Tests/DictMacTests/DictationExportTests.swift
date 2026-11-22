import DictCore
import Foundation
import XCTest

@testable import DictLocalAI

@MainActor
final class DictationExportTests: XCTestCase {
  func testPlainTXTContainsOnlyEditorTextAndNoReportMetadata() {
    let editedText = "Раз, два, три.\nИсправленный фрагмент."
    let bytes = TranscriptExporter.plainTextData(editedText)
    XCTAssertEqual(String(data: bytes, encoding: .utf8), editedText)
    XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("Таймкоды:"))
    XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("Источник:"))
  }

  func testJSONStillContainsOriginalSegmentTimesAndSpeakerMetadata() throws {
    var transcript = FileTranscript(source: "Диктовка", duration: 2.4)
    transcript.complete = true
    transcript.segments = [
      TranscriptSegment(
        start: 0.3, end: 2.2, text: "Раз, два, три.",
        speakerID: "1", channel: "microphone")
    ]
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: transcript.json()) as? [String: Any])
    let segments = try XCTUnwrap(json["segments"] as? [[String: Any]])
    let first = try XCTUnwrap(segments.first)
    XCTAssertEqual(first["start"] as? Double, 0.3)
    XCTAssertEqual(first["end"] as? Double, 2.2)
    XCTAssertEqual(first["speakerID"] as? String, "1")
    XCTAssertEqual(first["channel"] as? String, "microphone")
    XCTAssertEqual(first["text"] as? String, "Раз, два, три.")
    XCTAssertEqual(json["timestampBasis"] as? String, "seconds_from_session_start")
  }
}
