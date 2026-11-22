import DictApplication
import DictCore
import DictStorage
import Foundation
import XCTest

final class RecordingHistoryTests: XCTestCase {
  func testRetentionAndFailedDraftSaveThroughRepository() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = try RecordingStore(url: folder.appendingPathComponent("recordings.sqlite3"))
    let history = RecordingHistory(repository: { store })
    let now = Date(timeIntervalSince1970: 2_000_000)
    var document = FileTranscript(source: "Synthetic", duration: 2)
    document.segments = [
      TranscriptSegment(start: 1, end: 2, text: "Before", speakerID: "1", channel: "system")
    ]
    document.startedAt = now.addingTimeInterval(-8 * 86_400)
    _ = try store.create(document, category: .file, date: try XCTUnwrap(document.startedAt))
    document.startedAt = now
    _ = try store.create(document, category: .meeting, date: now)
    let entries = try history.recent(now: now)
    XCTAssertEqual(entries.map(\.category), [.meeting])
    let entry = try XCTUnwrap(entries.first)

    var draft = HistoryDraft(id: entry.id, document: try history.load(entry.id))
    draft.editSegment(3, text: "Out of range")
    XCTAssertFalse(draft.isDirty)
    draft.renameSpeaker("1", name: "Speaker")
    draft.editSegment(0, text: "After")
    XCTAssertTrue(try history.saveDraft(draft))
    draft.markSaved()
    XCTAssertFalse(draft.isDirty)
    let saved = try XCTUnwrap(history.load(entry.id))
    XCTAssertEqual(saved.speakerNames, ["1": "Speaker"])
    XCTAssertEqual(
      saved.segments,
      [TranscriptSegment(start: 1, end: 2, text: "After", speakerID: "1", channel: "system")])

    draft.editSegment(0, text: "Unsaved")
    try history.delete(entry.id)
    XCTAssertThrowsError(try history.saveDraft(draft))
    XCTAssertTrue(draft.isDirty)
    XCTAssertEqual(draft.document?.segments.first?.text, "Unsaved")
  }
}
