import AVFoundation
import DictCore
import XCTest

@testable import DictLocalAI

final class AudioCaptureTests: XCTestCase {
  func testTapConvertsOnBackgroundQueueAndIgnoresOldGeneration() async throws {
    let captured = CapturedAudio()
    let generation = UUID()
    captured.state.withLock {
      $0.running = true
      $0.generation = generation
    }
    let source = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let target = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let converter = try XCTUnwrap(AVAudioConverter(from: source, to: target))
    let tap = AudioCapture.makeTap(
      captured: captured, converter: converter, generation: generation,
      sampleRate: 48_000, interrupted: nil)
    try await Task.detached {
      XCTAssertFalse(Thread.isMainThread)
      let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
      buffer.frameLength = 4800
      let channel = try XCTUnwrap(buffer.floatChannelData?[0])
      for index in 0..<4800 { channel[index] = Float(sin(Double(index) * 0.1)) * 0.25 }
      tap(buffer, AVAudioTime(sampleTime: 0, atRate: 48_000))
      let count = captured.state.withLock { $0.samples.count }
      XCTAssertGreaterThan(count, 0)
      XCTAssertTrue(captured.state.withLock { $0.samples.allSatisfy { $0.isFinite } })
      XCTAssertGreaterThan(captured.state.withLock { $0.energy }, 0)
      captured.state.withLock { $0.generation = UUID() }
      tap(buffer, AVAudioTime(sampleTime: 4800, atRate: 48_000))
      XCTAssertEqual(captured.state.withLock { $0.samples.count }, count)
      captured.state.withLock { $0.running = false }
      tap(buffer, AVAudioTime(sampleTime: 9600, atRate: 48_000))
      XCTAssertEqual(captured.state.withLock { $0.samples.count }, count)
    }.value
  }
}
