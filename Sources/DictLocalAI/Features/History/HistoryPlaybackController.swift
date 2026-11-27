import AVFoundation
import Combine
import Foundation

/// One playing sound with a way to stop it and a callback for the natural end.
@MainActor
protocol ArchivedAudioPlayback: AnyObject {
  var onFinish: (() -> Void)? { get set }
  var currentTime: TimeInterval { get set }
  var duration: TimeInterval { get }
  func start() -> Bool
  func stop()
}

@MainActor
private final class AVArchivedAudioPlayback: NSObject, ArchivedAudioPlayback, AVAudioPlayerDelegate
{
  private let player: AVAudioPlayer
  var onFinish: (() -> Void)?

  init(url: URL) throws {
    player = try AVAudioPlayer(contentsOf: url)
    super.init()
    player.delegate = self
  }

  var currentTime: TimeInterval {
    get { player.currentTime }
    set { player.currentTime = newValue }
  }
  var duration: TimeInterval { player.duration }

  func start() -> Bool { player.play() }
  func stop() { player.stop() }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully: Bool) {
    Task { @MainActor in self.onFinish?() }
  }
}

private struct AudioPlaybackError: Error {}

/// Plays the saved sound of one history record. Local files only, one sound at a time.
@MainActor
final class HistoryPlaybackController: ObservableObject {
  /// Diagnostic reason playback ended.
  enum EndReason: String {
    case finished, stopped, switched
    case viewClosed = "view_closed"
  }

  @Published private(set) var playingRecordID: UUID?
  /// Seconds from the start of the playing record, 0 when nothing plays.
  @Published private(set) var position: TimeInterval = 0
  private(set) var duration: TimeInterval = 0
  private var ticker: Timer?
  private var playback: ArchivedAudioPlayback?
  private let directory: URL
  private let open: (URL) throws -> ArchivedAudioPlayback

  init(
    directory: URL = HistoryAudioFile.directory(in: Paths.root),
    open: @escaping (URL) throws -> ArchivedAudioPlayback = { try AVArchivedAudioPlayback(url: $0) }
  ) {
    self.directory = directory
    self.open = open
  }

  /// Resolve the local recording file if it is available.
  func fileURL(audioFile: String?) -> URL? {
    guard let audioFile, !audioFile.isEmpty,
      audioFile == (audioFile as NSString).lastPathComponent
    else { return nil }
    let url = directory.appendingPathComponent(audioFile)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  func isPlaying(_ id: UUID?) -> Bool { id != nil && playingRecordID == id }

  /// Starts the record, or stops it when it already plays. Throws when the file cannot be played.
  func toggle(id: UUID, audioFile: String?) throws {
    if isPlaying(id) {
      stop(reason: .stopped)
      return
    }
    try play(id: id, audioFile: audioFile, from: 0)
  }

  /// True while the position timer runs. It runs only while a sound plays.
  var isTracking: Bool { ticker != nil }

  /// Seek on drag completion or keyboard changes. Start playback if it is idle.
  func seek(id: UUID, audioFile: String?, to time: TimeInterval) throws {
    // Keep seeks within the playable portion of the file.
    let limit = (isPlaying(id) ? playback?.duration : nil).map { max(0, $0 - 0.1) }
    try play(
      id: id, audioFile: audioFile, from: min(max(0, time), limit ?? .infinity), source: "slider",
      clampToEnd: true)
  }

  /// Reads the current time of the playing sound.
  func updatePlaybackPosition() {
    guard let playback else { return }
    position = playback.currentTime
    duration = playback.duration
  }

  /// Start playback at the requested time, or seek if the same record is already playing.
  func play(
    id: UUID, audioFile: String?, from time: TimeInterval, source: String? = nil,
    clampToEnd: Bool = false
  ) throws {
    if isPlaying(id), let playback {
      guard time < playback.duration else { return reportSeekOutsideAudio() }
      playback.currentTime = max(0, time)
      position = playback.currentTime
      DiagnosticLog.shared.event(
        "history-audio", "play_seek",
        "from=\(DiagnosticFields.seconds(max(0, time)))" + (source.map { " source=\($0)" } ?? ""))
      return
    }
    guard let url = fileURL(audioFile: audioFile) else { return }
    do {
      let next = try open(url)
      // The recorded duration can exceed the playback file's actual length.
      let time = clampToEnd ? min(time, max(0, next.duration - 0.1)) : time
      if time > 0 {
        guard time < next.duration else { return reportSeekOutsideAudio() }
        next.currentTime = time
      }
      stop(reason: .switched)
      guard next.start() else { throw AudioPlaybackError() }
      next.onFinish = { [weak self, weak next] in
        guard let self, let next, self.playback === next else { return }
        self.finish(reason: .finished)
      }
      playback = next
      playingRecordID = id
      startPositionUpdates()
      updatePlaybackPosition()
      DiagnosticLog.shared.event(
        "history-audio", "play_started",
        "from=\(DiagnosticFields.seconds(time)) duration=\(DiagnosticFields.seconds(next.duration))"
      )
    } catch {
      DiagnosticLog.shared.event("history-audio", "play_failed", "error_type=\(type(of: error))")
      throw error
    }
  }

  func stop(reason: EndReason = .stopped) {
    playback?.onFinish = nil
    playback?.stop()
    finish(reason: reason)
  }

  private func startPositionUpdates() {
    ticker?.invalidate()
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.updatePlaybackPosition() }
    }
    // Continue updating playback position during slider tracking.
    RunLoop.main.add(timer, forMode: .common)
    ticker = timer
  }

  private func reportSeekOutsideAudio() {
    DiagnosticLog.shared.event("history-audio", "seek_out_of_range")
  }

  private func finish(reason: EndReason) {
    if playback != nil {
      DiagnosticLog.shared.event("history-audio", "play_ended", "reason=\(reason.rawValue)")
    }
    ticker?.invalidate()
    ticker = nil
    playback = nil
    playingRecordID = nil
    position = 0
    duration = 0
  }
}
