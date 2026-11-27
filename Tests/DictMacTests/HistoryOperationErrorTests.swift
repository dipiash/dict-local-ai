import DictApplication
import DictCore
import DictStorage
import XCTest

@testable import DictLocalAI

@MainActor
final class HistoryOperationErrorTests: XCTestCase {
  func testReloadPreservesAnFailureThatAnotherActionSetMeanwhile() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let recordings = try RecordingStore(url: folder.appendingPathComponent("recordings.sqlite3"))
    let store = HistoryStore(history: RecordingHistory(repository: { recordings }))
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertNil(store.error)

    store.reportSaveFailure(NSError(domain: "test", code: 1), category: .file)
    let shown = try XCTUnwrap(store.error)
    store.reload()
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(store.error, shown)
  }

  func testSuccessfulSaveDeletesTheSaveFailureItShowed() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let recordings = try RecordingStore(url: folder.appendingPathComponent("recordings.sqlite3"))
    let store = HistoryStore(history: RecordingHistory(repository: { recordings }))
    try await Task.sleep(for: .milliseconds(300))

    store.reportSaveFailure(NSError(domain: "test", code: 1), category: .dictation)
    XCTAssertNotNil(store.error)
    store.didSaveHistory()
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertNil(store.error)
  }

  func testSuccessfulClearDeletesTheClearFailureItShowed() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let recordings = try RecordingStore(url: folder.appendingPathComponent("recordings.sqlite3"))
    nonisolated(unsafe) var broken = false
    let store = HistoryStore(
      history: RecordingHistory(repository: {
        if broken { throw NSError(domain: "test", code: 2) }
        return recordings
      }))
    try await Task.sleep(for: .milliseconds(300))

    broken = true
    store.clear()
    XCTAssertNotNil(store.error)
    broken = false
    store.clear()
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertNil(store.error)
  }

  func testSuccessfulClearPreservesAnUnrelatedSaveFailure() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let recordings = try RecordingStore(url: folder.appendingPathComponent("recordings.sqlite3"))
    let store = HistoryStore(history: RecordingHistory(repository: { recordings }))
    try await Task.sleep(for: .milliseconds(300))

    store.reportSaveFailure(NSError(domain: "test", code: 1), category: .file)
    let shown = try XCTUnwrap(store.error)
    store.clear()
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(store.error, shown)
  }
  private func openMeetingStore() async throws -> (HistoryStore, RecordingStore, UUID, URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recordings = try RecordingStore(url: folder.appendingPathComponent("recordings.sqlite3"))
    var transcript = FileTranscript(source: "meeting", duration: 10)
    transcript.segments = [TranscriptSegment(start: 0, end: 5, text: "first", speakerID: "S1")]
    let id = try recordings.create(transcript, category: .meeting)
    let store = HistoryStore(history: RecordingHistory(repository: { recordings }))
    try await Task.sleep(for: .milliseconds(300))
    store.selectDraft(id)
    return (store, recordings, id, folder)
  }

  func testUneditedDraftReloadsWhenMeetingGrows() async throws {
    let (store, recordings, id, folder) = try await openMeetingStore()
    defer { try? FileManager.default.removeItem(at: folder) }

    try recordings.append(
      id, segments: [TranscriptSegment(start: 5, end: 9, text: "tail", speakerID: "S1")], until: 9)
    try recordings.finish(id, duration: 9, complete: true)
    store.reload()
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(store.draftDocument?.segments.map(\.text), ["first", "tail"])
  }

  func testStaleEditedDraftCannotOverwriteNewMeetingContent() async throws {
    let (store, recordings, id, folder) = try await openMeetingStore()
    defer { try? FileManager.default.removeItem(at: folder) }

    store.renameDraftSpeaker("S1", name: "Anna")
    try recordings.append(
      id, segments: [TranscriptSegment(start: 5, end: 9, text: "tail", speakerID: "S1")], until: 9)
    store.reload()
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertFalse(store.saveDraft())

    XCTAssertEqual(try recordings.load(id)?.segments.map(\.text), ["first", "tail"])
    XCTAssertNotNil(store.error)
  }

  func testSavingAnEditedDraftOfAnUnmodifiedRecordStillWorks() async throws {
    let (store, recordings, id, folder) = try await openMeetingStore()
    defer { try? FileManager.default.removeItem(at: folder) }

    store.editDraftSegment(0, text: "edited")
    XCTAssertTrue(store.saveDraft())
    try await Task.sleep(for: .milliseconds(300))
    store.editDraftSegment(0, text: "edited again")

    XCTAssertTrue(store.saveDraft())
    XCTAssertEqual(try recordings.load(id)?.segments.map(\.text), ["edited again"])
  }

  private func openRichStore(category: RecordingCategory) async throws -> (
    HistoryStore, RecordingStore, UUID, URL
  ) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recordings = try RecordingStore(url: folder.appendingPathComponent("recordings.sqlite3"))
    var transcript = FileTranscript(source: category.rawValue, duration: 12.3456789)
    transcript.startedAt = Date(timeIntervalSince1970: 1_700_000_000.123456)
    transcript.segments = [
      TranscriptSegment(start: 0.1, end: 4.7777777, text: "first", speakerID: "S1"),
      TranscriptSegment(start: 4.8, end: 9.3333333, text: "second", speakerID: "S2"),
    ]
    transcript.speakerNames = ["S1": "Anna"]
    transcript.asrWarnings = ["warn"]
    transcript.audioFile = "rec.m4a"
    let id = try recordings.create(transcript, category: category)
    let store = HistoryStore(history: RecordingHistory(repository: { recordings }))
    try await Task.sleep(for: .milliseconds(300))
    store.selectDraft(id)
    return (store, recordings, id, folder)
  }

  func testBothRecordCategoriesAllowSavingRichDraftTwice() async throws {
    for category in [RecordingCategory.meeting, .dictation] {
      let (store, recordings, id, folder) = try await openRichStore(category: category)
      defer { try? FileManager.default.removeItem(at: folder) }

      store.editDraftSegment(0, text: "one")
      XCTAssertTrue(store.saveDraft(), "\(category) first save")
      try await Task.sleep(for: .milliseconds(300))
      store.editDraftSegment(1, text: "two")
      XCTAssertTrue(store.saveDraft(), "\(category) second save")

      XCTAssertNil(store.error)
      XCTAssertEqual(try recordings.load(id)?.segments.map(\.text), ["one", "two"])
    }
  }

  func testReloadAfterOwnSavePreservesDraft() async throws {
    let (store, _, _, folder) = try await openRichStore(category: .meeting)
    defer { try? FileManager.default.removeItem(at: folder) }
    let log = try XCTUnwrap(DiagnosticLog.shared.activeLogURL)
    func refreshes() throws -> Int {
      try String(contentsOf: log, encoding: .utf8).components(separatedBy: "draft_refreshed").count
    }
    let before = try refreshes()

    store.editDraftSegment(0, text: "one")
    XCTAssertTrue(store.saveDraft())
    try await Task.sleep(for: .milliseconds(300))
    store.reload()
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(try refreshes(), before)
    XCTAssertEqual(store.draftDocument?.segments.first?.text, "one")
  }
}
