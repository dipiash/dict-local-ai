import AVFoundation
import DictCore

final class AudioFileReader {
  private let file: AVAudioFile
  let duration: Double
  let sampleCount: Int

  static func inspectDuration(_ url: URL) async throws -> Double {
    try await Task.detached(priority: .userInitiated) {
      try AudioFileReader(url: url).duration
    }.value
  }

  init(url: URL) throws {
    file = try AVAudioFile(forReading: url)
    let rate = file.processingFormat.sampleRate
    guard rate > 0, file.length > 0 else {
      throw AppFailure("audio.the-file-contains-no-audio")
    }
    duration = Double(file.length) / rate
    guard duration.isFinite, duration <= Double(FileTranscript.maximumSeconds) else {
      throw AppFailure("audio.choose-a-recording-no-longer")
    }
    sampleCount = Int(ceil(duration * Double(AudioWindow.sampleRate)))
  }

  func read(_ range: Range<Int>, session: RecognitionSession) throws -> [Float] {
    let inputFormat = file.processingFormat
    let ratio = inputFormat.sampleRate / Double(AudioWindow.sampleRate)
    let first = AVAudioFramePosition(floor(Double(range.lowerBound) * ratio))
    let last = min(file.length, AVAudioFramePosition(ceil(Double(range.upperBound) * ratio)))
    file.framePosition = first
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
        channels: 1, interleaved: false),
      let converter = AVAudioConverter(from: inputFormat, to: format),
      let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192),
      let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 8192)
    else { throw AppFailure("audio.could-not-prepare-the-audio") }
    var samples: [Float] = []
    let file = self.file
    nonisolated(unsafe) let conversionInput = input
    nonisolated(unsafe) var readError: Error?
    var finished = false
    while !finished {
      if session.cancelled { throw CancellationError() }
      var conversionError: NSError?
      let status = converter.convert(to: output, error: &conversionError) { requested, state in
        if session.cancelled || file.framePosition >= last || readError != nil {
          state.pointee = .endOfStream
          return nil
        }
        do {
          let count = min(
            AVAudioFrameCount(last - file.framePosition),
            min(requested, conversionInput.frameCapacity))
          try file.read(into: conversionInput, frameCount: count)
          state.pointee = conversionInput.frameLength == 0 ? .endOfStream : .haveData
          return conversionInput.frameLength == 0 ? nil : conversionInput
        } catch {
          readError = error
          state.pointee = .endOfStream
          return nil
        }
      }
      if let readError { throw readError }
      if let conversionError { throw conversionError }
      if status == .error { throw AppFailure("audio.could-not-decode-the-audio") }
      if let channel = output.floatChannelData?[0] {
        let count = min(Int(output.frameLength), range.count - samples.count)
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
      }
      finished = status == .endOfStream || samples.count >= range.count
      if output.frameLength == 0 && !finished {
        throw AppFailure("audio.decoding-stopped-before-the-end")
      }
    }
    return samples
  }
}
