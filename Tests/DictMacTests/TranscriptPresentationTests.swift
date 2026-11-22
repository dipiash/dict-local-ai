import DictCore
import Foundation
import XCTest

@testable import DictLocalAI

final class TranscriptPresentationTests: XCTestCase {
  func testSpeakerLabelsAndTimecodesInBothLanguages() throws {
    var transcript = FileTranscript(source: "call.wav", duration: 10_800)
    transcript.processedUntil = 3_625.125
    transcript.segments = [
      .init(start: 3_608, end: 3_616, text: "Да", speakerID: "1", channel: "microphone"),
      .init(start: 3_624, end: 3_625.125, text: "Test", channel: "system"),
    ]
    for language in ["en", "ru"] {
      let text = try formatter(language)
      let report = transcript.plainText(using: text)
      if language == "en" {
        XCTAssertTrue(report.contains("Processed: Partial, up to 01:00:25"))
        XCTAssertTrue(report.contains("[01:00:08–01:00:16] [Microphone] Speaker 1: Да"))
        XCTAssertTrue(report.contains("[System Audio] Unknown Speaker: Test"))
      } else {
        XCTAssertTrue(report.contains("Обработано: Частично, до 01:00:25"))
        XCTAssertTrue(report.contains("[01:00:08–01:00:16] [Микрофон] Спикер 1: Да"))
        XCTAssertTrue(report.contains("[Звук компьютера] Спикер не определён: Test"))
      }
    }
  }

  func testASROnlyReportOmitsSpeakerLabels() throws {
    var transcript = FileTranscript(source: "speech.wav", duration: 1)
    transcript.speakerRecognitionEnabled = false
    transcript.diarizationMethod = "diarization-failed"
    transcript.complete = true
    transcript.segments = [.init(start: 0, end: 1, text: "Test")]
    let report = transcript.plainText(using: try formatter("en"))
    XCTAssertTrue(report.contains("Processed: Complete"))
    XCTAssertTrue(report.contains("Speaker recognition mode: diarization-failed"))
    XCTAssertTrue(report.contains("[00:00:00.0–00:00:01.0] Test"))
    XCTAssertFalse(report.contains("Unknown Speaker"))
  }

  private func formatter(_ language: String) throws -> (String, [CVarArg]) -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let file = root.appendingPathComponent("Resources/App/\(language).lproj/Localizable.strings")
    let values = try PropertyListSerialization.propertyList(
      from: Data(contentsOf: file), format: nil)
    let catalog = try XCTUnwrap(values as? [String: String])
    return { key, arguments in
      String(format: catalog[key] ?? key, arguments: arguments)
    }
  }
}
