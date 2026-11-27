import XCTest

@testable import DictCore

final class ZeroSampleAudioTests: XCTestCase {
  private let second = [Float](repeating: 0, count: 16_000)

  func testTwoMinutesOfDigitalSilenceTriggersOneWarning() {
    var tracker = SilentAudioMonitor()
    var events: [SilentAudioMonitor.Event] = []
    for t in 0..<130 {
      if let event = tracker.append(second, at: Double(t)) { events.append(event) }
    }
    XCTAssertEqual(events, [.warningRaised(seconds: 120)])
  }

  func testSilenceThresholdSuppressesEarlyWarnings() {
    var tracker = SilentAudioMonitor()
    for t in 0..<119 { XCTAssertNil(tracker.append(second, at: Double(t))) }
  }

  func testCurrentSilentSecondsTracksTheActiveZeroRun() {
    var tracker = SilentAudioMonitor()
    XCTAssertEqual(tracker.ongoingSilenceSeconds, 0)
    for t in 0..<30 { _ = tracker.append(second, at: Double(t)) }
    XCTAssertEqual(tracker.ongoingSilenceSeconds, 30)
    _ = tracker.append([Float](repeating: 0.1, count: 16_000), at: 30)
    XCTAssertEqual(tracker.ongoingSilenceSeconds, 0)
  }

  func testNonzeroQuietSamplesAreNotClassifiedAsSilence() {
    var tracker = SilentAudioMonitor()
    let quiet = [Float](repeating: 0.0001, count: 16_000)
    for t in 0..<300 { XCTAssertNil(tracker.append(quiet, at: Double(t))) }
  }

  func testOneNonzeroSampleEndsSilenceRun() {
    var tracker = SilentAudioMonitor()
    for t in 0..<100 { _ = tracker.append(second, at: Double(t)) }
    var blip = second
    blip[500] = 0.00001
    XCTAssertNil(tracker.append(blip, at: 100))
    for t in 101..<200 { XCTAssertNil(tracker.append(second, at: Double(t))) }
  }

  func testResumeRecordsSilentSecondsExclusivelyAfterWarning() {
    var tracker = SilentAudioMonitor()
    for t in 0..<130 { _ = tracker.append(second, at: Double(t)) }
    let sound = [Float](repeating: 0.1, count: 16_000)
    XCTAssertEqual(tracker.append(sound, at: 130), .resumed(silentSeconds: 130))
    XCTAssertNil(tracker.append(sound, at: 131))

    var shortGap = SilentAudioMonitor()
    for t in 0..<30 { _ = shortGap.append(second, at: Double(t)) }
    XCTAssertNil(shortGap.append(sound, at: 30))
  }

  func testProgressNotificationOnEachNewMinute() {
    var tracker = SilentAudioMonitor()
    var events: [SilentAudioMonitor.Event] = []
    for t in 0..<250 {
      if let event = tracker.append(second, at: Double(t)) { events.append(event) }
    }
    let expected: [SilentAudioMonitor.Event] = [
      .warningRaised(seconds: 120),
      .warningProgress(seconds: 180),
      .warningProgress(seconds: 240),
    ]
    XCTAssertEqual(events, expected)
  }

  func testTimestampGapTalliesAsSilence() {
    var tracker = SilentAudioMonitor()
    XCTAssertNil(tracker.append(second, at: 0))
    XCTAssertEqual(tracker.append(second, at: 200), .warningRaised(seconds: 201))
  }

  func testWindowGateExclusivelyForExactZeros() {
    XCTAssertTrue(ZeroSampleAudio.isSilent([Float](repeating: 0, count: 100)))
    XCTAssertFalse(ZeroSampleAudio.isSilent([0, 0, 0.00001]))
    XCTAssertFalse(ZeroSampleAudio.isSilent([]))
  }

  /// Fake decoder: one token per 1280-sample frame whose first sample is non-zero.
  private func run(skipSilent: Bool, audio: [Float]) throws -> (times: [Double], calls: Int) {
    var buffer = MeetingAudioBuffer()
    var selector = WordBoundarySelector()
    var times: [Double] = []
    var calls = 0
    func drain(final: Bool) {
      while let batch = buffer.take(final: final) {
        if skipSilent && ZeroSampleAudio.isSilent(batch.samples) { continue }
        calls += 1
        var tokens: [RecognizedToken] = []
        for frame in 0..<(batch.samples.count / AudioWindow.frameSamples)
        where batch.samples[frame * AudioWindow.frameSamples] != 0 {
          let first = batch.window.read.lowerBound + frame * AudioWindow.frameSamples
          let time = Double(first) / 16_000
          tokens.append(RecognizedToken(time: time + batch.offset, piece: " w"))
        }
        let keep = batch.window.keep
        times += selector.select(
          tokens: tokens, start: batch.offset + Double(keep.lowerBound) / 16_000,
          end: batch.offset + Double(keep.upperBound) / 16_000,
          hasRightContext: batch.window.read.upperBound > keep.upperBound
        ).tokens.map(\.time)
      }
    }
    var position = 0
    while position < audio.count {
      let end = min(audio.count, position + 16_000)
      try buffer.append(Array(audio[position..<end]), at: Double(position) / 16_000)
      drain(final: false)
      position = end
    }
    drain(final: true)
    return (times, calls)
  }

  func testSkippingZeroWindowsPreservesTokenTimestamps() throws {
    var audio = [Float](repeating: 0, count: 80 * 16_000)
    for frame in 0..<10 { audio[frame * 1_280] = 0.2 }
    for frame in 0..<10 { audio[60 * 16_000 + frame * 1_280] = 0.2 }
    let withSkip = try run(skipSilent: true, audio: audio)
    let without = try run(skipSilent: false, audio: audio)
    XCTAssertEqual(withSkip.times, without.times)
    XCTAssertFalse(withSkip.times.isEmpty)
    XCTAssertGreaterThan(withSkip.times.last ?? 0, 59.9)
    XCTAssertLessThan(withSkip.calls, without.calls)
  }
}
