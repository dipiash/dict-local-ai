import AVFoundation
import XCTest

@testable import DictLocalAI

final class HistoryAudioFileTests: XCTestCase {
  private func readSavedSamples(_ url: URL, frames: AVAudioFramePosition) -> AVAudioFile? {
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
      if let file = try? AVAudioFile(forReading: url), file.length == frames { return file }
      Thread.sleep(forTimeInterval: 0.05)
    }
    return nil
  }

  func testStoresLosslessAudioAndFillsGapsWithSilence() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let audio = try HistoryAudioFile(kind: .meeting, directory: folder)
    let tone = (0..<16_000).map { Float(sin(Double($0) * 0.1) * 0.5) }
    audio.write(tone, at: 0)
    audio.write(tone, at: 2)
    audio.write(tone, at: 2.5)
    audio.close()

    let file = try XCTUnwrap(
      readSavedSamples(folder.appendingPathComponent(audio.name), frames: 56_000))
    XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
    XCTAssertEqual(file.fileFormat.channelCount, 1)
    XCTAssertEqual(
      file.fileFormat.settings[AVFormatIDKey] as? UInt32, kAudioFormatAppleLossless)
    let buffer = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 56_000))
    try file.read(into: buffer)
    let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 56_000)
    XCTAssertEqual(samples[16_000..<32_000].map(abs).max(), 0)
    XCTAssertEqual(samples[100], tone[100], accuracy: 0.001)
    XCTAssertEqual(samples[32_100], tone[100], accuracy: 0.001)
    // Discard the overlapping half second and keep the remaining audio on the timeline.
    XCTAssertEqual(samples[48_000], tone[8_000], accuracy: 0.001)
  }

  func testDiscardDeletesTheFile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let audio = try HistoryAudioFile(kind: .meeting, directory: folder)
    audio.write([0.1, 0.2], at: 0)
    audio.discard()
    let url = folder.appendingPathComponent(audio.name)
    let deadline = Date().addingTimeInterval(10)
    while FileManager.default.fileExists(atPath: url.path), Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testCloseNowDeletesAnBlankFileAndPreservesAudio() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let empty = try HistoryAudioFile(kind: .meeting, directory: folder)
    XCTAssertFalse(empty.finalizeSynchronously())
    let emptyURL = folder.appendingPathComponent(empty.name)
    XCTAssertFalse(FileManager.default.fileExists(atPath: emptyURL.path))

    let audio = try HistoryAudioFile(kind: .meeting, directory: folder)
    audio.write([0.1, 0.2], at: 0)
    XCTAssertTrue(audio.finalizeSynchronously())
    let url = folder.appendingPathComponent(audio.name)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
  }

  func testSilencePlanFillsUpToTheLimitAndBypassesTheRest() {
    XCTAssertTrue(HistoryAudioFile.planGapPadding(gap: 0, limit: 100) == (0, 0))
    XCTAssertTrue(HistoryAudioFile.planGapPadding(gap: -5, limit: 100) == (0, 0))
    XCTAssertTrue(HistoryAudioFile.planGapPadding(gap: 60, limit: 100) == (60, 0))
    XCTAssertTrue(HistoryAudioFile.planGapPadding(gap: 1_000, limit: 100) == (100, 900))
  }

  func testCopyOfAAbsentSourceRecordsItAndLeavesNoFile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let missing = folder.appendingPathComponent("missing.wav")
    let reported = expectation(description: "unreadable source reported")
    nonisolated(unsafe) var reportedName: String?
    let audio = try XCTUnwrap(
      HistoryAudioFile.copy(
        from: missing, directory: folder,
        onUnreadable: { name in
          reportedName = name
          reported.fulfill()
        }))
    wait(for: [reported], timeout: 5)
    XCTAssertEqual(reportedName, audio.name)
    _ = audio.finalizeSynchronously()
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    XCTAssertTrue(names.isEmpty)
  }

  func testCopyPreservesTheWholeImportedFile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source.wav")
    let format = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
    // Release the writer to finalize the audio file.
    do {
      let wav = try AVAudioFile(forWriting: source, settings: format.settings)
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
      buffer.frameLength = 16_000
      for index in 0..<16_000 { buffer.floatChannelData![0][index] = 0.25 }
      try wav.write(from: buffer)
    }

    let audio = try XCTUnwrap(HistoryAudioFile.copy(from: source, directory: folder))
    XCTAssertNotNil(readSavedSamples(folder.appendingPathComponent(audio.name), frames: 16_000))
  }

  func testCopyWithALimitPreservesExclusivelyTheProcessedPart() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("long.wav")
    let format = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
    let total: AVAudioFrameCount = 16_000 * 150
    do {
      let wav = try AVAudioFile(forWriting: source, settings: format.settings)
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total))
      buffer.frameLength = total
      for index in 0..<Int(total) { buffer.floatChannelData![0][index] = 0.25 }
      try wav.write(from: buffer)
    }

    let audio = try XCTUnwrap(
      HistoryAudioFile.copy(from: source, limitSeconds: 70, directory: folder))
    XCTAssertTrue(audio.finalizeSynchronously())
    let file = try AVAudioFile(forReading: folder.appendingPathComponent(audio.name))
    XCTAssertEqual(file.length, 70 * 16_000)
  }

  func testFinishAtQuitClosesAStoredDictationBeforeReturning() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let audio = try HistoryAudioFile(kind: .meeting, directory: folder)
    audio.write([Float](repeating: 0.25, count: 32_000), at: 0)
    audio.close()
    audio.finalizeBeforeExit()
    // Require a finalized audio file immediately after the call.
    let file = try AVAudioFile(forReading: folder.appendingPathComponent(audio.name))
    XCTAssertEqual(file.length, 32_000)
  }

  func testFinishAtQuitEndsACopyOnAMinuteBoundaryWithAValidFile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("long.wav")
    let format = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
    let total: AVAudioFrameCount = 16_000 * 150
    do {
      let wav = try AVAudioFile(forWriting: source, settings: format.settings)
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total))
      buffer.frameLength = total
      for index in 0..<Int(total) { buffer.floatChannelData![0][index] = 0.25 }
      try wav.write(from: buffer)
    }

    let audio = try XCTUnwrap(HistoryAudioFile.copy(from: source, directory: folder))
    audio.finalizeBeforeExit()
    let file = try AVAudioFile(forReading: folder.appendingPathComponent(audio.name))
    XCTAssertLessThanOrEqual(file.length, AVAudioFramePosition(total))
    // Cancellation takes effect only after a complete minute or when the copy has finished.
    if file.length != AVAudioFramePosition(total) { XCTAssertEqual(file.length % 960_000, 0) }
  }

  private func logText() throws -> String {
    try String(contentsOf: XCTUnwrap(DiagnosticLog.shared.activeLogURL), encoding: .utf8)
  }

  func testAudioDiagnosticsIncludeCategoryAndAbbreviatedIdentifier() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let kept = try HistoryAudioFile(kind: .dictation, directory: folder)
    kept.write([0.1, 0.2], at: 0)
    XCTAssertTrue(kept.finalizeSynchronously())
    let dropped = try HistoryAudioFile(kind: .file, directory: folder)
    dropped.discard()
    _ = dropped.finalizeSynchronously()
    kept.finalizeBeforeExit()

    let text = try logText()
    let keptID = String(kept.name.prefix(8))
    XCTAssertTrue(
      text.contains("[history-audio] closed kind=dictation audio=\(keptID) seconds=0"), text)
    XCTAssertTrue(
      text.contains("[history-audio] discarded kind=file audio=\(String(dropped.name.prefix(8)))"))
    XCTAssertTrue(text.contains("[history-audio] quit_wait kind=dictation ms="))
    XCTAssertFalse(text.contains(kept.name), "The full file name must not be logged")
  }
}
