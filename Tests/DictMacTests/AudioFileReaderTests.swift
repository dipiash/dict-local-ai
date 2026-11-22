import AVFoundation
import DictCore
import XCTest

@testable import DictLocalAI

final class AudioFileReaderTests: XCTestCase {
  func testStereoConversionAndShortTail() throws {
    for rate in [44_100.0, 48_000.0] {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString + ".wav")
      defer { try? FileManager.default.removeItem(at: url) }
      try writeFixture(url, rate: rate)
      let reader = try AudioFileReader(url: url)
      XCTAssertEqual(reader.duration, 17.125, accuracy: 1 / rate)
      var cursor = 0
      while let window = AudioWindow.next(start: cursor, available: reader.sampleCount, final: true)
      {
        let audio = try reader.read(window.read, session: RecognitionSession())
        XCTAssertLessThanOrEqual(abs(audio.count - window.read.count), 2)
        XCTAssertTrue(audio.allSatisfy { $0.isFinite })
        XCTAssertGreaterThan(audio.map { abs($0) }.max() ?? 0, 0.01)
        cursor = window.keep.upperBound
      }
      XCTAssertEqual(cursor, reader.sampleCount)
      let cancelled = RecognitionSession()
      cancelled.cancel()
      XCTAssertThrowsError(try reader.read(0..<16_000, session: cancelled)) {
        XCTAssertTrue($0 is CancellationError)
      }
    }
  }
  func testOfflineSampleSourceKeepsAudioInMemoryAndSupportsRandomAccess() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".wav")
    defer { try? FileManager.default.removeItem(at: url) }
    try writeFixture(url, rate: 48_000)
    let session = RecognitionSession()
    let source = try FileAudioSampleSource(url: url, session: session)
    XCTAssertEqual(source.sampleCount, Int(ceil(17.125 * 16_000)))
    let range = 16_000..<20_096
    var actual = [Float](repeating: .nan, count: range.count)
    try actual.withUnsafeMutableBufferPointer { buffer in
      try source.copySamples(
        into: try XCTUnwrap(buffer.baseAddress), offset: range.lowerBound,
        count: range.count)
    }
    let expected = try AudioFileReader(url: url).read(range, session: RecognitionSession())
    XCTAssertEqual(actual.count, expected.count)
    for (left, right) in zip(actual, expected) {
      XCTAssertEqual(left, right, accuracy: 0.0001)
    }
    XCTAssertTrue(actual.allSatisfy(\.isFinite))
    let tailCount = 100
    let tailOffset = source.sampleCount - tailCount
    let expectedTail = try AudioFileReader(url: url).read(
      tailOffset..<source.sampleCount, session: RecognitionSession())
    actual = [Float](repeating: .nan, count: range.count)
    try actual.withUnsafeMutableBufferPointer { buffer in
      try source.copySamples(
        into: try XCTUnwrap(buffer.baseAddress), offset: tailOffset, count: buffer.count)
    }
    for (left, right) in zip(actual, expectedTail) {
      XCTAssertEqual(left, right, accuracy: 0.0001)
    }
    XCTAssertTrue(actual.dropFirst(expectedTail.count).allSatisfy { $0 == 0 })
    XCTAssertTrue(actual.allSatisfy(\.isFinite))
    actual = [Float](repeating: .nan, count: range.count)
    try actual.withUnsafeMutableBufferPointer { buffer in
      try source.copySamples(
        into: try XCTUnwrap(buffer.baseAddress), offset: source.sampleCount, count: buffer.count)
    }
    XCTAssertTrue(actual.allSatisfy { $0 == 0 })
    XCTAssertThrowsError(
      try actual.withUnsafeMutableBufferPointer { buffer in
        try source.copySamples(
          into: try XCTUnwrap(buffer.baseAddress), offset: source.sampleCount + 1,
          count: buffer.count)
      })
    session.cancel()
    XCTAssertThrowsError(
      try actual.withUnsafeMutableBufferPointer { buffer in
        try source.copySamples(
          into: try XCTUnwrap(buffer.baseAddress), offset: range.lowerBound,
          count: buffer.count)
      }
    ) { error in
      XCTAssertTrue(error is CancellationError)
    }
  }

  private func writeFixture(_ url: URL, rate: Double) throws {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
    let count = AVAudioFrameCount(17.125 * rate)
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
    buffer.frameLength = count
    let channels = try XCTUnwrap(buffer.floatChannelData)
    for index in 0..<Int(count) {
      let value = Float(sin(Double(index) * 2 * .pi * 440 / rate)) * 0.2
      channels[0][index] = value
      channels[1][index] = value
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
  }
}
