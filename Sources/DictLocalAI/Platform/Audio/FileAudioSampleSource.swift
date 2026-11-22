import DictCore
import FluidAudio
import Foundation

final class FileAudioSampleSource: @unchecked Sendable {
  let sampleCount: Int
  private let reader: AudioFileReader
  private let session: RecognitionSession
  private let lock = NSLock()

  init(url: URL, session: RecognitionSession) throws {
    let reader = try AudioFileReader(url: url)
    self.reader = reader
    self.session = session
    sampleCount = reader.sampleCount
  }

  func copySamples(into destination: UnsafeMutablePointer<Float>, offset: Int, count: Int) throws {
    guard count > 0 else { return }
    guard offset >= 0, offset <= sampleCount else {
      throw AppFailure("audio.speaker-recognition-requested-audio-outside")
    }
    if session.cancelled { throw CancellationError() }
    lock.lock()
    defer { lock.unlock() }
    // FluidAudio can request samples past the end of the file.
    let available = min(count, sampleCount - offset)
    let samples =
      available > 0
      ? try reader.read(offset..<(offset + available), session: session) : []
    let copied = min(count, samples.count)
    if copied > 0 {
      samples.withUnsafeBufferPointer { buffer in
        if let base = buffer.baseAddress {
          destination.update(from: base, count: copied)
        }
      }
    }
    if copied < count {
      memset(destination.advanced(by: copied), 0, (count - copied) * MemoryLayout<Float>.size)
    }
  }
}
