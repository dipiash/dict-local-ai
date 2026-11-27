import DictApplication
import DictCore
import DictStorage
import Foundation
import XCTest

final class HistoryAudioCleanupTests: XCTestCase {
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

  private func write(_ name: String, bytes: Int = 4, age: TimeInterval = 3_600) throws {
    let url = audio.appendingPathComponent(name)
    FileManager.default.createFile(atPath: url.path, contents: Data(count: bytes))
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
  }

  private func record(
    _ store: RecordingStore, audioFile: String?, text: String = "Synthetic words",
    category: RecordingCategory = .dictation
  ) throws -> UUID {
    var document = FileTranscript(source: "Synthetic title", duration: 7)
    document.audioFile = audioFile
    document.segments = [TranscriptSegment(start: 0, end: 1, text: text)]
    return try store.create(document, category: category)
  }

  private func exists(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: audio.appendingPathComponent(name).path)
  }

  func testRemovingAllAudioPreservesTextsAndResetsAudioFile() throws {
    let store = try store()
    try write("a.m4a", bytes: 10)
    try write("b.m4a", bytes: 20)
    let first = try record(store, audioFile: "a.m4a", text: "First text")
    let second = try record(store, audioFile: "b.m4a", text: "Second text", category: .meeting)
    let noAudio = try record(store, audioFile: nil, text: "Third text")
    let before = try store.list(category: nil)

    let removal = try store.clearSavedAudio(active: { [] })

    XCTAssertEqual(removal, AudioCleanupResult(files: 2, bytes: 30, skippedActive: 0))
    XCTAssertFalse(exists("a.m4a"))
    XCTAssertFalse(exists("b.m4a"))
    for (id, text) in [(first, "First text"), (second, "Second text"), (noAudio, "Third text")] {
      let loaded = try XCTUnwrap(store.load(id))
      XCTAssertNil(loaded.audioFile)
      XCTAssertEqual(loaded.segments.map(\.text), [text])
      XCTAssertEqual(loaded.source, "Synthetic title")
      XCTAssertEqual(loaded.duration, 7)
    }
    XCTAssertEqual(try store.list(category: nil), before)
    XCTAssertEqual(store.audioUsage(), AudioStorageUsage(files: 0, bytes: 0))
  }

  func testCleanupRemovesOrphanAudio() throws {
    let store = try store()
    try write("orphan.m4a", bytes: 5)
    let removal = try store.clearSavedAudio(active: { [] })
    XCTAssertEqual(removal.files, 1)
    XCTAssertFalse(exists("orphan.m4a"))
  }

  func testAudioOfARecordingInProgressRemainsLinked() throws {
    let store = try store()
    try write("live.m4a", bytes: 8)
    try write("old.m4a", bytes: 3)
    let live = try record(store, audioFile: "live.m4a", text: "Live text", category: .meeting)
    let old = try record(store, audioFile: "old.m4a")

    let removal = try store.clearSavedAudio(active: { ["live.m4a"] })

    XCTAssertEqual(removal, AudioCleanupResult(files: 1, bytes: 3, skippedActive: 1))
    XCTAssertTrue(exists("live.m4a"))
    XCTAssertFalse(exists("old.m4a"))
    XCTAssertEqual(try store.load(live)?.audioFile, "live.m4a")
    XCTAssertEqual(try store.load(live)?.segments.map(\.text), ["Live text"])
    XCTAssertNil(try store.load(old)?.audioFile)
  }

  func testCleanupProtectsRecentAudioBeforeRecordCommit() throws {
    let store = try store()
    try write("fresh.m4a", age: 1)
    try write("stale.m4a", age: 3_600)
    let removal = try store.clearSavedAudio(active: { [] })
    XCTAssertEqual(removal.files, 1)
    XCTAssertEqual(removal.skippedActive, 1)
    XCTAssertTrue(exists("fresh.m4a"))
    XCTAssertFalse(exists("stale.m4a"))
  }

  func testUsageTalliesFilesAndBytesAndIgnoresHiddenFiles() throws {
    let store = try store()
    try write("a.m4a", bytes: 100)
    try write("b.m4a", bytes: 250)
    try write(".DS_Store", bytes: 999)
    XCTAssertEqual(store.audioUsage(), AudioStorageUsage(files: 2, bytes: 350))
  }

  func testBulkAudioCleanupIsIdempotent() throws {
    let store = try store()
    try write("a.m4a")
    _ = try record(store, audioFile: "a.m4a")
    _ = try store.clearSavedAudio(active: { [] })
    XCTAssertEqual(
      try store.clearSavedAudio(active: { [] }),
      AudioCleanupResult(files: 0, bytes: 0, skippedActive: 0))
  }

  func testUpdateCannotRestoreClearedAudioReference() throws {
    let store = try store()
    try write("a.m4a")
    let id = try record(store, audioFile: "a.m4a")
    var stale = try XCTUnwrap(store.load(id))
    _ = try store.clearSavedAudio(active: { [] })

    stale.segments = [TranscriptSegment(start: 0, end: 1, text: "Edited text")]
    try store.replace(id, transcript: stale)

    let loaded = try XCTUnwrap(store.load(id))
    XCTAssertNil(loaded.audioFile)
    XCTAssertEqual(loaded.segments.map(\.text), ["Edited text"])
  }

  func testReplacePreservesTheNameOfAFileThatStillExists() throws {
    let store = try store()
    try write("live.m4a")
    let id = try record(store, audioFile: "live.m4a")
    var document = try XCTUnwrap(store.load(id))
    document.segments = [TranscriptSegment(start: 0, end: 1, text: "Edited text")]
    try store.replace(id, transcript: document)
    XCTAssertEqual(try store.load(id)?.audioFile, "live.m4a")
  }

  func testUpdatingRecordCanAttachNewlyAvailableAudio() throws {
    let store = try store()
    let id = try record(store, audioFile: nil)
    try write("late.m4a")
    var document = try XCTUnwrap(store.load(id))
    document.audioFile = "late.m4a"
    try store.replace(id, transcript: document)
    XCTAssertEqual(try store.load(id)?.audioFile, "late.m4a")
  }

  func testRecordsCanBeStoredAndReadWhileAudioFilesAreBeingDeleted() throws {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let store = try RecordingStore(
      url: folder.appendingPathComponent("recordings.sqlite3"), audioDirectory: audio,
      onEvent: { _, _ in },
      removeFile: { url in
        started.signal()
        release.wait()
        return (try? FileManager.default.removeItem(at: url)) != nil
      })
    try write("a.m4a")
    let id = try record(store, audioFile: "a.m4a")
    let removal = expectation(description: "removal finished")
    DispatchQueue.global().async {
      _ = try? store.clearSavedAudio(active: { [] })
      removal.fulfill()
    }
    XCTAssertEqual(started.wait(timeout: .now() + 5), .success)

    let other = expectation(description: "save and read finished")
    DispatchQueue.global().async {
      _ = try? store.create(FileTranscript(source: "New", duration: 1), category: .dictation)
      _ = try? store.load(id)
      other.fulfill()
    }
    let result = XCTWaiter().wait(for: [other], timeout: 3)
    release.signal()
    wait(for: [removal], timeout: 5)
    XCTAssertEqual(result, .completed, "create and load waited for the file deletion")
    XCTAssertFalse(exists("a.m4a"))
  }
}
