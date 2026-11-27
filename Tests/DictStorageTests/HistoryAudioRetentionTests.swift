import DictCore
import DictStorage
import Foundation
import XCTest

final class HistoryAudioRetentionTests: XCTestCase {
  private var folder: URL!
  private var audio: URL { folder.appendingPathComponent("Audio", isDirectory: true) }

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func store() throws -> RecordingStore {
    try RecordingStore(
      url: folder.appendingPathComponent("recordings.sqlite3"), audioDirectory: audio)
  }

  private func record(
    _ store: RecordingStore, audioFile: String, category: RecordingCategory = .dictation,
    date: Date = Date()
  ) throws -> UUID {
    FileManager.default.createFile(
      atPath: audio.appendingPathComponent(audioFile).path, contents: Data([1]))
    var document = FileTranscript(source: "Synthetic", duration: 1)
    document.audioFile = audioFile
    document.segments = [TranscriptSegment(start: 0, end: 1, text: "Text")]
    return try store.create(document, category: category, date: date)
  }

  private func exists(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: audio.appendingPathComponent(name).path)
  }

  func testDeletingRecordAlsoDeletesAudio() throws {
    let store = try store()
    let kept = try record(store, audioFile: "kept.m4a")
    let removed = try record(store, audioFile: "removed.m4a")
    try store.delete(removed)
    XCTAssertFalse(exists("removed.m4a"))
    XCTAssertTrue(exists("kept.m4a"))
    XCTAssertEqual(try store.load(kept)?.audioFile, "kept.m4a")
  }

  func testClearingACategoryDeletesExclusivelyItsAudio() throws {
    let store = try store()
    _ = try record(store, audioFile: "meeting.m4a", category: .meeting)
    _ = try record(store, audioFile: "file.m4a", category: .file)
    try store.deleteAll(category: .meeting)
    XCTAssertFalse(exists("meeting.m4a"))
    XCTAssertTrue(exists("file.m4a"))
    try store.deleteAll(category: nil)
    XCTAssertFalse(exists("file.m4a"))
  }

  func testClearingHistoryRemovesOnlyAgedOrphanAudio() throws {
    let store = try store()
    _ = try record(store, audioFile: "linked.m4a")
    let orphan = audio.appendingPathComponent("orphan.m4a")
    FileManager.default.createFile(atPath: orphan.path, contents: Data([1]))
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-3_600)], ofItemAtPath: orphan.path)
    FileManager.default.createFile(
      atPath: audio.appendingPathComponent("in-progress.m4a").path, contents: Data([1]))

    try store.deleteAll(category: nil)

    XCTAssertFalse(exists("linked.m4a"))
    XCTAssertFalse(exists("orphan.m4a"))
    XCTAssertTrue(exists("in-progress.m4a"))
  }

  func testPruningRemovesExpiredAndAgedOrphanAudio() throws {
    let store = try store()
    let now = Date()
    _ = try record(store, audioFile: "old.m4a", date: now.addingTimeInterval(-31 * 86_400))
    _ = try record(store, audioFile: "recent.m4a", date: now.addingTimeInterval(-29 * 86_400))
    let orphan = audio.appendingPathComponent("orphan.m4a")
    FileManager.default.createFile(atPath: orphan.path, contents: Data([1]))
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-31 * 86_400)], ofItemAtPath: orphan.path)
    FileManager.default.createFile(
      atPath: audio.appendingPathComponent("in-progress.m4a").path, contents: Data([1]))

    try store.prune(retentionDays: 30, now: now)

    XCTAssertFalse(exists("old.m4a"))
    XCTAssertFalse(exists("orphan.m4a"))
    XCTAssertTrue(exists("recent.m4a"))
    XCTAssertTrue(exists("in-progress.m4a"))
  }

  func testAudioPathsStayInsideStorage() throws {
    let store = try store()
    let outside = folder.appendingPathComponent("outside.txt")
    FileManager.default.createFile(atPath: outside.path, contents: Data([1]))
    var document = FileTranscript(source: "Synthetic", duration: 1)
    document.audioFile = "../outside.txt"
    let id = try store.create(document, category: .file)
    try store.delete(id)
    XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
  }
}
