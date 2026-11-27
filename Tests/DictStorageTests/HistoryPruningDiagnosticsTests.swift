import DictCore
import DictStorage
import Foundation
import XCTest

private final class Events: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String] = []
  func add(_ value: String) { lock.withLock { values.append(value) } }
  var all: [String] { lock.withLock { values } }
}

final class HistoryPruningDiagnosticsTests: XCTestCase {
  private var folder: URL!
  private var audio: URL { folder.appendingPathComponent("Audio", isDirectory: true) }

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func makeStore(_ events: Events) throws -> RecordingStore {
    try RecordingStore(
      url: folder.appendingPathComponent("recordings.sqlite3"), audioDirectory: audio
    ) { name, details in events.add("\(name) \(details)") }
  }

  func testPruningDiagnosticsRecordCountsAndAudioOrigin() throws {
    let events = Events()
    let store = try makeStore(events)
    let now = Date()
    FileManager.default.createFile(
      atPath: audio.appendingPathComponent("old.m4a").path, contents: Data([1]))
    var document = FileTranscript(source: "Synthetic", duration: 1)
    document.audioFile = "old.m4a"
    _ = try store.create(document, category: .dictation, date: now.addingTimeInterval(-31 * 86_400))
    let orphan = audio.appendingPathComponent("orphan.m4a")
    FileManager.default.createFile(atPath: orphan.path, contents: Data([1]))
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-31 * 86_400)], ofItemAtPath: orphan.path)

    try store.prune(retentionDays: 30, now: now)

    let logged = events.all
    XCTAssertTrue(logged.contains("audio_removed source=record files=1 linked=1"), "\(logged)")
    XCTAssertTrue(logged.contains("audio_removed source=orphan files=1 linked=1"), "\(logged)")
    let prune = try XCTUnwrap(logged.first { $0.hasPrefix("prune_ok") })
    XCTAssertTrue(prune.hasPrefix("prune_ok days=30 rows=1 ms="), prune)
  }

  func testPruneThatDeletesNothingIsNotLogged() throws {
    let events = Events()
    let store = try makeStore(events)
    try store.prune(retentionDays: 30)
    XCTAssertFalse(events.all.contains { $0.hasPrefix("prune_ok") })
    XCTAssertFalse(events.all.contains { $0.hasPrefix("audio_removed") })
  }
}
