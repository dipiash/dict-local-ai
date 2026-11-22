import DictCore
import DictStorage
import Foundation
import XCTest

final class RecordingStoreRoundTripTests: XCTestCase {
  func testStructuredHistorySurvivesReopenEditAndRetention() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("recordings.sqlite")
    let now = Date(timeIntervalSince1970: 2_000_000)
    let boundary = now.addingTimeInterval(-7 * 86_400)
    var transcript = FileTranscript(source: "Synthetic recording", duration: 18)
    transcript.startedAt = boundary
    transcript.processedUntil = 11.25
    transcript.speakerNames = ["1": "Speaker A"]
    transcript.speakerRecognitionEnabled = true
    transcript.segments = [
      TranscriptSegment(
        start: 3.75, end: 11.25, text: "One voice", speakerID: "1", channel: "system")
    ]
    let ids: [UUID]
    do {
      let original = try RecordingStore(url: url)
      ids = [
        try original.create(transcript, category: .dictation, date: now),
        try original.create(transcript, category: .meeting, date: boundary),
        try original.create(transcript, category: .file, date: boundary.addingTimeInterval(-1)),
      ]
    }

    let reopened = try RecordingStore(url: url)
    for id in ids { XCTAssertEqual(try reopened.load(id), transcript) }
    transcript.speakerNames["1"] = "Edited speaker"
    try reopened.replace(ids[1], transcript: transcript)
    XCTAssertEqual(try reopened.load(ids[1]), transcript)
    let exported = try XCTUnwrap(reopened.load(ids[1])).json()
    XCTAssertEqual(try JSONDecoder().decode(FileTranscript.self, from: exported), transcript)
    try reopened.prune(retentionDays: 7, now: now)
    XCTAssertEqual(try reopened.list().map(\.id), Array(ids.prefix(2)))
    XCTAssertNil(try reopened.load(ids[2]))
  }
}
