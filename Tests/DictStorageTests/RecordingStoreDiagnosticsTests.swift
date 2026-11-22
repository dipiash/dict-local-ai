import DictCore
import DictStorage
import Foundation
import XCTest

private final class EventCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String] = []

  func append(_ value: String) {
    lock.lock()
    values.append(value)
    lock.unlock()
  }

  func snapshot() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }
}

final class RecordingStoreDiagnosticsTests: XCTestCase {
  func testMetadataOnlyLoggingCoversRecordingLifecycleAndFailures() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("dict-history-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let collector = EventCollector()
    let store = try RecordingStore(url: directory.appendingPathComponent("recordings.sqlite3")) {
      event, metadata in collector.append("\(event) \(metadata)")
    }
    var document = FileTranscript(source: "PRIVATE-FILENAME.m4a", duration: 12)
    document.segments = [
      TranscriptSegment(start: 0, end: 3, text: "PRIVATE RECOGNIZED WORDS")
    ]
    document.processedUntil = 3

    let id = try store.create(document, category: .file)
    XCTAssertEqual(try store.list(category: .file).count, 1)
    XCTAssertEqual(try store.load(id)?.segments.count, 1)
    try store.append(
      id, segments: [TranscriptSegment(start: 3, end: 5, text: "SECRET TRANSCRIPT")], until: 5)
    XCTAssertEqual(try store.load(id)?.segments.count, 2)
    document.complete = true
    document.processedUntil = 12
    try store.replace(id, transcript: document)
    try store.finish(id, duration: 12, complete: true)
    try store.prune(retentionDays: 7)

    XCTAssertThrowsError(try store.create(document, category: .file, id: id))
    try store.delete(id)
    XCTAssertNil(try store.load(id))
    try store.deleteAll(category: .file)

    let logged = collector.snapshot().joined(separator: "\n")
    for event in [
      "open_ok", "create_ok", "list_ok", "load_ok", "append_ok", "replace_ok",
      "finish_ok", "prune_ok", "create_failed", "delete_ok", "deleteAll_ok",
    ] {
      XCTAssertTrue(logged.contains(event), "Missing \(event)")
    }
    XCTAssertFalse(logged.contains("PRIVATE-FILENAME"))
    XCTAssertFalse(logged.contains("PRIVATE RECOGNIZED WORDS"))
    XCTAssertFalse(logged.contains("SECRET TRANSCRIPT"))
    XCTAssertTrue(logged.contains("sqlite_code="))
  }
}
