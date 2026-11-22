import AVFoundation
import Foundation
import Synchronization
import XCTest

@testable import DictLocalAI

final class SystemAudioTapCaptureTests: XCTestCase {
  @MainActor
  func testSystemAudioCallbacksResampleOffMainAndStopAfterFailure() async throws {
    let processor = MeetingAudioProcessor()
    let counts = Mutex((samples: 0, failures: 0))
    let failed = expectation(description: "tap failure reported on MainActor")
    processor.state.withLock {
      $0.accepted = true
      $0.onSamples = { samples, timestamp in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertEqual(timestamp, 1)
        counts.withLock { $0.samples += samples.count }
      }
      $0.onFailure = { _ in
        MainActor.assertIsolated()
        counts.withLock { $0.failures += 1 }
        failed.fulfill()
      }
    }
    let tap = processor.makeAudioHandler()
    let fail = processor.makeFailureHandler()
    try await Task.detached {
      XCTAssertFalse(Thread.isMainThread)
      let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
      buffer.frameLength = 4800
      let channel = try XCTUnwrap(buffer.floatChannelData?[0])
      for index in 0..<4800 { channel[index] = Float(sin(Double(index) * 0.1)) * 0.25 }
      tap(buffer, 1)
      XCTAssertGreaterThan(counts.withLock { $0.samples }, 0)
      fail("Synthetic tap failure")
      let before = counts.withLock { $0.samples }
      tap(buffer, 1)
      XCTAssertEqual(counts.withLock { $0.samples }, before)
    }.value
    let result = await XCTWaiter.fulfillment(of: [failed], timeout: 1)
    XCTAssertEqual(result, .completed)
    XCTAssertEqual(counts.withLock { $0.failures }, 1)
  }

  func testStopBeforeStartDoesNotRequestSystemPermission() async {
    let capture = SystemAudioTapCapture(onAudio: { _, _ in }, onFailure: { _ in })
    await capture.stop()
  }

  func testAppDeclaresSystemAudioPurposeWithoutScreenCapture() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Resources/App/Info.plist"))
    let propertyList = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let description = try XCTUnwrap(propertyList["NSAudioCaptureUsageDescription"] as? String)
    XCTAssertFalse(description.isEmpty)
    XCTAssertNotNil(propertyList["NSMicrophoneUsageDescription"])
  }
}
