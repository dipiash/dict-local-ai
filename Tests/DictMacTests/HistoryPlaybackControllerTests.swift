import Combine
import DictApplication
import XCTest

@testable import DictLocalAI

@MainActor
final class HistoryPlaybackControllerTests: XCTestCase {
  private final class FakePlayback: ArchivedAudioPlayback {
    var onFinish: (() -> Void)?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 60
    var started = false
    var stopped = false
    func start() -> Bool {
      started = true
      return true
    }
    func stop() { stopped = true }
  }

  private var folder: URL!
  private var fake: FakePlayback!
  private var player: HistoryPlaybackController!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    fake = FakePlayback()
    let fake = fake!
    player = HistoryPlaybackController(directory: folder, open: { _ in fake })
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: folder)
  }

  private func makeFile(_ name: String) throws {
    try Data([1]).write(to: folder.appendingPathComponent(name))
  }

  func testOffersExclusivelyExistingFilesWithPlainNames() throws {
    try makeFile("a.m4a")
    XCTAssertNotNil(player.fileURL(audioFile: "a.m4a"))
    XCTAssertNil(player.fileURL(audioFile: "missing.m4a"))
    XCTAssertNil(player.fileURL(audioFile: nil))
    XCTAssertNil(player.fileURL(audioFile: ""))
    XCTAssertNil(player.fileURL(audioFile: "../a.m4a"))
  }

  func testToggleBeginsThenEnds() throws {
    try makeFile("a.m4a")
    let id = UUID()
    try player.toggle(id: id, audioFile: "a.m4a")
    XCTAssertTrue(player.isPlaying(id))
    XCTAssertTrue(fake.started)
    try player.toggle(id: id, audioFile: "a.m4a")
    XCTAssertFalse(player.isPlaying(id))
    XCTAssertTrue(fake.stopped)
  }

  func testNaturalPlaybackCompletionClearsPlayerState() throws {
    try makeFile("a.m4a")
    let id = UUID()
    try player.toggle(id: id, audioFile: "a.m4a")
    fake.onFinish?()
    XCTAssertNil(player.playingRecordID)
    XCTAssertFalse(player.isPlaying(id))
  }

  func testAbsentFileAndNilNameStartNothing() throws {
    try player.toggle(id: UUID(), audioFile: "missing.m4a")
    try player.toggle(id: UUID(), audioFile: nil)
    XCTAssertNil(player.playingRecordID)
    XCTAssertFalse(fake.started)
  }

  func testStopResetsAndStartingAnotherRecordEndsTheFirst() throws {
    try makeFile("a.m4a")
    let first = UUID()
    try player.toggle(id: first, audioFile: "a.m4a")
    player.stop()
    XCTAssertNil(player.playingRecordID)
    XCTAssertTrue(fake.stopped)

    let second = UUID()
    try player.toggle(id: second, audioFile: "a.m4a")
    XCTAssertTrue(player.isPlaying(second))
    XCTAssertFalse(player.isPlaying(first))
  }

  func testUnopenableFileThrowsAndRemainsIdle() throws {
    try makeFile("a.m4a")
    let broken = HistoryPlaybackController(
      directory: folder, open: { _ in throw CocoaError(.fileReadCorruptFile) })
    XCTAssertThrowsError(try broken.toggle(id: UUID(), audioFile: "a.m4a"))
    XCTAssertNil(broken.playingRecordID)
  }

  func testPlaybackRejectsExistingNonAudioFile() throws {
    try makeFile("a.m4a")
    let real = HistoryPlaybackController(directory: folder)
    XCTAssertThrowsError(try real.toggle(id: UUID(), audioFile: "a.m4a"))
    XCTAssertNil(real.playingRecordID)
  }

  func testPlayBeginsFromGivenTime() throws {
    try makeFile("a.m4a")
    let id = UUID()
    try player.play(id: id, audioFile: "a.m4a", from: 12.5)
    XCTAssertTrue(player.isPlaying(id))
    XCTAssertEqual(fake.currentTime, 12.5)
    XCTAssertTrue(fake.started)
  }

  func testPlayInsideActiveRecordJumpsWithoutStop() throws {
    try makeFile("a.m4a")
    let id = UUID()
    try player.play(id: id, audioFile: "a.m4a", from: 5)
    try player.play(id: id, audioFile: "a.m4a", from: 30)
    XCTAssertEqual(fake.currentTime, 30)
    XCTAssertFalse(fake.stopped)
    XCTAssertTrue(player.isPlaying(id))
  }

  func testStartBeyondAudioEndLeavesPlaybackIdle() throws {
    try makeFile("a.m4a")
    let id = UUID()
    try player.play(id: id, audioFile: "a.m4a", from: 61)
    XCTAssertNil(player.playingRecordID)
    XCTAssertFalse(fake.started)

    try player.play(id: id, audioFile: "a.m4a", from: 10)
    try player.play(id: id, audioFile: "a.m4a", from: 90)
    XCTAssertEqual(fake.currentTime, 10)
    XCTAssertTrue(player.isPlaying(id))
  }

  func testPlayingAnotherRecordFromTimeEndsThePrevious() throws {
    try makeFile("a.m4a")
    let first = UUID()
    let second = UUID()
    try player.play(id: first, audioFile: "a.m4a", from: 3)
    try player.play(id: second, audioFile: "a.m4a", from: 8)
    XCTAssertTrue(fake.stopped)
    XCTAssertTrue(player.isPlaying(second))
    XCTAssertFalse(player.isPlaying(first))
  }

  private func logLines() throws -> [String] {
    let url = try XCTUnwrap(DiagnosticLog.shared.activeLogURL)
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
  }

  func testPlaybackStoresStartSeekAndEndEvents() throws {
    try makeFile("a.m4a")
    fake.duration = 91.37
    try player.play(id: UUID(), audioFile: "a.m4a", from: 12.34)
    try player.play(id: player.playingRecordID!, audioFile: "a.m4a", from: 41.26)
    player.stop(reason: .viewClosed)

    let lines = try logLines()
    XCTAssertTrue(
      lines.contains { $0.hasSuffix("[history-audio] play_started from=12.3 duration=91.4") },
      "\(lines.suffix(8))")
    XCTAssertTrue(lines.contains { $0.hasSuffix("[history-audio] play_seek from=41.3") })
    XCTAssertTrue(lines.contains { $0.hasSuffix("[history-audio] play_ended reason=view_closed") })
  }

  func testPlaybackEndLogsNaturalStopAndRecordSwitch() throws {
    try makeFile("a.m4a")
    let before = try logLines().count
    try player.toggle(id: UUID(), audioFile: "a.m4a")
    fake.onFinish?()
    try player.toggle(id: UUID(), audioFile: "a.m4a")
    try player.toggle(id: player.playingRecordID!, audioFile: "a.m4a")
    try player.toggle(id: UUID(), audioFile: "a.m4a")
    try player.toggle(id: UUID(), audioFile: "a.m4a")

    let ended = try logLines().dropFirst(before).filter { $0.contains("play_ended") }
    XCTAssertEqual(
      ended.compactMap { $0.split(separator: " ").last(where: { $0.hasPrefix("reason=") }) },
      ["reason=finished", "reason=stopped", "reason=switched"])
  }

  func testPositionTracksPlaybackExclusivelyAfterRefresh() throws {
    try makeFile("a.m4a")
    XCTAssertEqual(player.position, 0)
    XCTAssertFalse(player.isTracking)
    try player.toggle(id: UUID(), audioFile: "a.m4a")
    XCTAssertTrue(player.isTracking)
    XCTAssertEqual(player.duration, 60)
    fake.currentTime = 17.5
    player.updatePlaybackPosition()
    XCTAssertEqual(player.position, 17.5)
  }

  func testSliderSeekUpdatesActivePlaybackAndWritesDiagnostic() throws {
    try makeFile("a.m4a")
    let id = UUID()
    try player.toggle(id: id, audioFile: "a.m4a")
    try player.seek(id: id, audioFile: "a.m4a", to: 33)
    XCTAssertEqual(fake.currentTime, 33)
    XCTAssertEqual(player.position, 33)
    XCTAssertFalse(fake.stopped)
    XCTAssertTrue(
      try logLines().contains { $0.hasSuffix("[history-audio] play_seek from=33.0 source=slider") })
  }

  func testSeekOnIdleRecordBeginsFromThatTime() throws {
    try makeFile("a.m4a")
    let id = UUID()
    try player.seek(id: id, audioFile: "a.m4a", to: 12)
    XCTAssertTrue(player.isPlaying(id))
    XCTAssertEqual(fake.currentTime, 12)
    XCTAssertEqual(player.position, 12)
  }

  func testSeekToTheEndRemainsInsideTheRecord() throws {
    try makeFile("a.m4a")
    let id = UUID()
    try player.toggle(id: id, audioFile: "a.m4a")
    try player.seek(id: id, audioFile: "a.m4a", to: 60)
    XCTAssertTrue(player.isPlaying(id))
    XCTAssertEqual(fake.currentTime, 59.9, accuracy: 0.001)
  }

  func testSeekOnIdleRecordPastTheFileEndRemainsInsideTheFile() throws {
    try makeFile("a.m4a")
    let id = UUID()
    try player.seek(id: id, audioFile: "a.m4a", to: 90)
    XCTAssertTrue(player.isPlaying(id))
    XCTAssertEqual(fake.currentTime, 59.9, accuracy: 0.001)
  }

  func testEndOfRecordResetsPositionAndEndsTimer() throws {
    try makeFile("a.m4a")
    try player.toggle(id: UUID(), audioFile: "a.m4a")
    fake.currentTime = 59
    player.updatePlaybackPosition()
    fake.onFinish?()
    XCTAssertEqual(player.position, 0)
    XCTAssertEqual(player.duration, 0)
    XCTAssertFalse(player.isTracking)
  }

  func testSelectingDifferentRecordClearsPlaybackPosition() throws {
    try makeFile("a.m4a")
    try player.play(id: UUID(), audioFile: "a.m4a", from: 40)
    XCTAssertEqual(player.position, 40)
    player.stop(reason: .switched)
    XCTAssertEqual(player.position, 0)
    XCTAssertFalse(player.isTracking)
    try player.toggle(id: UUID(), audioFile: "a.m4a")
    XCTAssertEqual(player.position, fake.currentTime)
  }

  func testHistoryListRefreshesOnPlaybackStateTransitionsOnly() async throws {
    try makeFile("a.m4a")
    let store = HistoryStore(
      history: RecordingHistory(repository: { throw CocoaError(.fileNoSuchFile) }), audio: player)
    // Let the first reload finish, so its own change is not counted.
    try await Task.sleep(for: .milliseconds(300))
    var redraws = 0
    let sub = store.objectWillChange.sink { redraws += 1 }
    defer { sub.cancel() }

    try player.toggle(id: UUID(), audioFile: "a.m4a")
    XCTAssertEqual(redraws, 1)
    fake.currentTime = 10
    player.updatePlaybackPosition()
    fake.currentTime = 11
    player.updatePlaybackPosition()
    XCTAssertEqual(redraws, 1)
    player.stop()
    XCTAssertEqual(redraws, 2)
  }
}
