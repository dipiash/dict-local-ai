import DictApplication
import DictCore
import Foundation
import XCTest

@testable import DictLocalAI

final class MeetingJournalTests: XCTestCase {
  private func withFolder(_ body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder)
  }

  func testJournalCanBeListedEditedAndIndividuallyDeleted() throws {
    try withFolder { folder in
      var document = FileTranscript(source: "Тестовая встреча", duration: 0)
      document.startedAt = Date()
      let journal = MeetingJournal(directory: folder)
      let id = journal.begin(document)
      journal.append(
        [TranscriptSegment(start: 0, end: 2, text: "Исходный текст", speakerID: "1")], until: 2)
      journal.finish(duration: 2, complete: true)
      let entries = try journal.saved(retentionDays: RecordingRetention.days, now: Date())
      XCTAssertEqual(entries.count, 1)
      XCTAssertEqual(entries.first?.id, id)
      document = try XCTUnwrap(entries.first?.transcript)
      XCTAssertTrue(document.complete)
      XCTAssertEqual(document.segments.first?.text, "Исходный текст")
      document.speakerNames["1"] = "Анна"
      document.segments[0] = TranscriptSegment(
        start: 0, end: 2, text: "Исправленный текст", speakerID: "1")
      try journal.save(document, to: id)
      let restored = try XCTUnwrap(journal.read(id))
      XCTAssertEqual(restored.speakerNames["1"], "Анна")
      XCTAssertEqual(restored.segments.first?.text, "Исправленный текст")
      let permissions =
        try FileManager.default.attributesOfItem(
          atPath: folder.appendingPathComponent("recordings.sqlite3").path)[.posixPermissions]
        as? NSNumber
      XCTAssertEqual(permissions?.intValue, 0o600)
      try journal.delete(id)
      XCTAssertTrue(try journal.saved(retentionDays: RecordingRetention.days, now: Date()).isEmpty)
    }
  }

  func testFinalizationSupersedesProvisionalLabelsOnDisk() throws {
    try withFolder { folder in
      let journal = MeetingJournal(directory: folder)
      let id = journal.begin(FileTranscript(source: "Test", duration: 0))
      journal.append(
        [TranscriptSegment(start: 0, end: 3, text: "one", speakerID: nil)], until: 3)
      journal.replaceSegments(
        [TranscriptSegment(start: 0, end: 3, text: "one", speakerID: "1")])
      journal.finish(duration: 3, complete: true)
      let restored = try XCTUnwrap(journal.read(id))
      XCTAssertEqual(restored.segments.count, 1)
      XCTAssertEqual(restored.segments[0].speakerID, "1")
      XCTAssertTrue(restored.complete)
    }
  }

  func testDeleteAllWaitsForPendingWritesAndAllowsNewMeeting() throws {
    try withFolder { folder in
      let journal = MeetingJournal(directory: folder)
      journal.begin(FileTranscript(source: "Удаляемая встреча", duration: 0))
      journal.finish(duration: 0, complete: true)
      try journal.deleteAll()
      XCTAssertTrue(try journal.saved(retentionDays: RecordingRetention.days, now: Date()).isEmpty)
      journal.begin(FileTranscript(source: "Новая встреча", duration: 0))
      journal.finish(duration: 0, complete: true)
      XCTAssertEqual(
        try journal.saved(retentionDays: RecordingRetention.days, now: Date()).map(
          \.transcript.source), ["Новая встреча"])
    }
  }

  func testUnfinishedMeetingPreservesPreviouslySavedTranscript() throws {
    try withFolder { folder in
      let journal = MeetingJournal(directory: folder)
      let id = journal.begin(FileTranscript(source: "Восстановление", duration: 0))
      journal.append([TranscriptSegment(start: 0, end: 1, text: "Сохранённый текст")], until: 1)
      let restored = try XCTUnwrap(journal.read(id))
      XCTAssertEqual(restored.source, "Восстановление")
      XCTAssertEqual(restored.segments.first?.text, "Сохранённый текст")
      XCTAssertFalse(restored.complete)
    }
  }

  func testEditingRecordLeavesExpirationUnchanged() throws {
    try withFolder { folder in
      var document = FileTranscript(source: "Старая встреча", duration: 1)
      document.startedAt = Date().addingTimeInterval(-31 * 86400)
      let journal = MeetingJournal(directory: folder)
      let id = try journal.save(document)
      document.segments = [TranscriptSegment(start: 0, end: 1, text: "Правка")]
      try journal.save(document, to: id)
      XCTAssertEqual(try journal.read(id)?.segments.first?.text, "Правка")
      XCTAssertTrue(try journal.saved(retentionDays: RecordingRetention.days, now: Date()).isEmpty)
      XCTAssertNil(try journal.read(id))
    }
  }

  @MainActor
  func testAutosaveTogglePreservesOneRecordWithFullTextAndOneAudioFile() throws {
    try withFolder { folder in
      let audioDirectory = HistoryAudioFile.directory(in: folder)
      try FileManager.default.createDirectory(
        at: audioDirectory, withIntermediateDirectories: true)
      let audioName = "\(UUID().uuidString).caf"
      let audioURL = audioDirectory.appendingPathComponent(audioName)
      try Data([1, 2, 3]).write(to: audioURL)
      let journal = MeetingJournal(directory: folder)
      let workflow = MeetingWorkflow(modes: ModeCoordinator(), journal: journal)
      var document = workflow.makeTranscript(title: "Toggle", startedAt: Date())
      document.audioFile = audioName
      var transcript: FileTranscript? = document
      let id = try XCTUnwrap(workflow.beginAutosave(document, enabled: true, onError: { _ in }))
      workflow.append(
        [TranscriptSegment(start: 0, end: 1, text: "before")], until: 1, elapsed: 1,
        to: &transcript)
      _ = workflow.setAutosave(
        false, state: .recording, elapsed: 2, transcript: transcript, onError: { _ in })
      workflow.append(
        [TranscriptSegment(start: 1, end: 2, text: "while off")], until: 2, elapsed: 2,
        to: &transcript)
      let resumed = workflow.setAutosave(
        true, state: .recording, elapsed: 2, transcript: transcript, onError: { _ in })
      workflow.append(
        [TranscriptSegment(start: 2, end: 3, text: "after")], until: 3, elapsed: 3,
        to: &transcript)
      workflow.finalize(&transcript, elapsed: 3, reason: .requested)

      XCTAssertEqual(resumed, id)
      let records = try journal.saved(retentionDays: RecordingRetention.days, now: Date())
      XCTAssertEqual(records.map(\.id), [id])
      XCTAssertEqual(
        records.first?.transcript.segments.map(\.text), ["before", "while off", "after"])
      XCTAssertEqual(records.first?.transcript.audioFile, audioName)
      XCTAssertEqual(records.first?.transcript.complete, true)

      try journal.delete(id)
      XCTAssertTrue(try journal.saved(retentionDays: RecordingRetention.days, now: Date()).isEmpty)
      XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }
  }
}
