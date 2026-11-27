import AVFoundation
import DictCore
import Foundation
import Synchronization

// Store one mono 16 kHz Apple Lossless file per record and remove it with that record.
final class HistoryAudioFile: @unchecked Sendable {
  private static let rate = Double(AudioWindow.sampleRate)
  private static let chunk = AudioWindow.sampleRate * 60

  static func directory(in root: URL) -> URL {
    root.appendingPathComponent("Audio", isDirectory: true)
  }

  enum Kind: String { case dictation, meeting, file }

  // Keep open audio files out of bulk deletion.
  private static let openAudioFilenames = Mutex<Set<String>>([])
  static var active: Set<String> { openAudioFilenames.withLock { $0 } }

  let name: String
  let kind: Kind
  private let url: URL
  // One queue per file, so stopping a meeting never waits for another file's copy.
  private let queue = DispatchQueue(label: "dict.recording.audio", qos: .utility)
  // Only touched on `queue`.
  private var file: AVAudioFile?
  private var storedFrames: Int64 = 0
  // Frames of a huge clock jump that were not filled with silence.
  private var skipped: Int64 = 0
  private let stopLock = NSLock()
  private var importCancellationRequested = false

  init(kind: Kind, directory: URL = HistoryAudioFile.directory(in: Paths.data)) throws {
    self.kind = kind
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let fileName = UUID().uuidString.lowercased() + ".m4a"
    name = fileName
    Self.openAudioFilenames.withLock { _ = $0.insert(fileName) }
    url = directory.appendingPathComponent(fileName)
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatAppleLossless,
      AVSampleRateKey: Self.rate,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitDepthHintKey: 16,
    ]
    do {
      file = try AVAudioFile(
        forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    } catch {
      Self.openAudioFilenames.withLock { _ = $0.remove(fileName) }
      throw error
    }
  }

  /// Splits a gap into silence to write and frames to skip, so a clock jump is paid for once.
  static func planGapPadding(gap: Int64, limit: Int64) -> (pad: Int64, skip: Int64) {
    guard gap > 0 else { return (0, 0) }
    return (min(gap, limit), max(0, gap - limit))
  }

  /// Writes samples placed at `seconds`; gaps become silence so file time matches transcript time.
  func write(_ samples: [Float], at seconds: Double) {
    queue.async { [self] in
      guard file != nil, seconds.isFinite else { return }
      let target = Int64((max(0, seconds) * Self.rate).rounded()) - skipped
      var input = samples[...]
      if target < storedFrames {
        input = input.dropFirst(Int(min(storedFrames - target, Int64(input.count))))
      }
      let plan = Self.planGapPadding(
        gap: target - storedFrames, limit: Int64(FileTranscript.maximumSeconds) * Int64(Self.rate))
      skipped += plan.skip
      var gap = plan.pad
      while gap > 0 {
        let count = Int(min(gap, Int64(Self.chunk)))
        append(ArraySlice(repeating: 0, count: count))
        gap -= Int64(count)
      }
      append(input)
    }
  }

  func close() {
    queue.async { [self] in _ = finalizeOutput() }
  }

  /// Finalize the file synchronously and report whether it was retained.
  func finalizeSynchronously() -> Bool {
    queue.sync { finalizeOutput() }
  }

  private var logID: String { "kind=\(kind.rawValue) audio=\(DiagnosticFields.audioID(name))" }

  private func finalizeOutput() -> Bool {
    file = nil
    Self.openAudioFilenames.withLock { _ = $0.remove(name) }
    if storedFrames == 0 { try? FileManager.default.removeItem(at: url) }
    DiagnosticLog.shared.event(
      "history-audio", "closed", "\(logID) seconds=\(Int(Double(storedFrames) / Self.rate))")
    return storedFrames > 0
  }

  /// Quit path: stops a running copy at the next minute and waits until the file is closed.
  func finalizeBeforeExit() {
    let began = ProcessInfo.processInfo.systemUptime
    stopLock.withLock { importCancellationRequested = true }
    queue.sync {}
    let millis = Int((ProcessInfo.processInfo.systemUptime - began) * 1_000)
    DiagnosticLog.shared.event(
      "history-audio", "quit_wait", "kind=\(kind.rawValue) ms=\(millis)")
  }

  private var shouldStopImport: Bool { stopLock.withLock { importCancellationRequested } }

  func discard() {
    queue.async { [self] in
      file = nil
      Self.openAudioFilenames.withLock { _ = $0.remove(name) }
      try? FileManager.default.removeItem(at: url)
      DiagnosticLog.shared.event("history-audio", "discarded", logID)
    }
  }

  private func append(_ samples: ArraySlice<Float>) {
    guard let file, !samples.isEmpty,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
      let channel = buffer.floatChannelData?[0]
    else { return }
    samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    do {
      try file.write(from: buffer)
      storedFrames += Int64(samples.count)
    } catch {
      self.file = nil
      DiagnosticLog.shared.event(
        "history-audio", "write_failed", "\(logID) \(DiagnosticFields.error(error))")
    }
  }

  /// Saves already captured samples, for example a finished dictation.
  static func save(
    _ samples: [Float], enabled: Bool = true,
    directory: URL = HistoryAudioFile.directory(in: Paths.data)
  ) -> HistoryAudioFile? {
    guard !samples.isEmpty,
      let audio = make(kind: .dictation, enabled: enabled, directory: directory)
    else { return nil }
    audio.write(samples, at: 0)
    audio.close()
    return audio
  }

  /// Convert the import to 16 kHz audio in one-minute chunks.
  /// `onUnreadable` gets the file name on the main queue when the source cannot be opened.
  /// `limitSeconds` keeps only the processed part of a canceled transcription.
  static func copy(
    from source: URL, enabled: Bool = true, limitSeconds: Double? = nil,
    directory: URL = HistoryAudioFile.directory(in: Paths.data),
    onUnreadable: @escaping @Sendable (String) -> Void = { _ in }
  ) -> HistoryAudioFile? {
    guard let audio = make(kind: .file, enabled: enabled, directory: directory) else { return nil }
    // Open the source on the file queue to avoid blocking the main thread.
    audio.queue.async {
      let scoped = source.startAccessingSecurityScopedResource()
      defer { if scoped { source.stopAccessingSecurityScopedResource() } }
      let reader: AudioFileReader
      do { reader = try AudioFileReader(url: source) } catch {
        audio.file = nil
        try? FileManager.default.removeItem(at: audio.url)
        DiagnosticLog.shared.event("history-audio", "copy_failed", "reason=unreadable_source")
        let name = audio.name
        DispatchQueue.main.async { onUnreadable(name) }
        return
      }
      do {
        let session = RecognitionSession()
        var start = 0
        var total = reader.sampleCount
        if let limitSeconds, limitSeconds.isFinite {
          let limit = Int((max(0, limitSeconds) * rate).rounded(.up))
          if limit < total {
            total = limit
            DiagnosticLog.shared.event(
              "history-audio", "copy_stopped",
              "reason=cancel \(audio.logID) seconds=\(limit / AudioWindow.sampleRate)")
          }
        }
        while start < total {
          let end = min(total, start + chunk)
          audio.append(try reader.read(start..<end, session: session)[...])
          start = end
          // At least one minute is kept, so the history record never points to a missing file.
          if start < total, audio.shouldStopImport {
            let seconds = start / AudioWindow.sampleRate
            DiagnosticLog.shared.event(
              "history-audio", "copy_stopped", "reason=quit seconds=\(seconds)")
            break
          }
        }
      } catch {
        DiagnosticLog.shared.event("history-audio", "copy_failed", "error_type=\(type(of: error))")
      }
    }
    audio.close()
    return audio
  }

  /// `enabled` is the "Save audio" setting: when off, no file is created at all.
  static func make(
    kind: Kind, enabled: Bool = true, directory: URL = HistoryAudioFile.directory(in: Paths.data)
  ) -> HistoryAudioFile? {
    guard enabled else { return nil }
    do { return try HistoryAudioFile(kind: kind, directory: directory) } catch {
      DiagnosticLog.shared.event(
        "history-audio", "open_failed", "kind=\(kind.rawValue) error_type=\(type(of: error))")
      return nil
    }
  }
}
