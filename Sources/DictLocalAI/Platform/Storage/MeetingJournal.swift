import DictApplication
import DictCore
import DictStorage
import Foundation
import Synchronization

final class MeetingJournal: MeetingJournalPort, Sendable {
  private static let writer = DispatchQueue(label: "dict.meeting.journal", qos: .utility)
  private let folder: URL
  private let selected = Mutex<UUID?>(nil)
  private let errorHandler = Mutex<@MainActor @Sendable (Error) -> Void>({ _ in })

  init(directory: URL = MeetingJournal.directory) { folder = directory }

  var onError: @MainActor @Sendable (Error) -> Void {
    get { errorHandler.withLock { $0 } }
    set { errorHandler.withLock { $0 = newValue } }
  }

  static var directory: URL { Paths.root }

  private static func database(in folder: URL) throws -> RecordingStore {
    if folder.standardizedFileURL == directory.standardizedFileURL {
      return try RecordingDatabase.require()
    }
    return try RecordingStore(
      url: folder.appendingPathComponent("recordings.sqlite3"),
      audioDirectory: HistoryAudioFile.directory(in: folder),
      onEvent: { event, details in DiagnosticLog.shared.event("history-db", event, details) })
  }

  @discardableResult func begin(_ transcript: FileTranscript) -> UUID {
    let id = UUID()
    selected.withLock { $0 = id }
    DiagnosticLog.shared.event("history-meeting", "begin_queued", "id=\(id.uuidString.prefix(8))")
    Self.writer.async {
      do {
        _ = try Self.database(in: self.folder).create(
          transcript, category: .meeting, id: id,
          date: transcript.startedAt ?? Date())
      } catch { self.fail(error) }
    }
    return id
  }

  func resumeRecord(_ id: UUID, with transcript: FileTranscript) {
    selected.withLock { $0 = id }
    DiagnosticLog.shared.event(
      "meeting", "autosave_resumed",
      "record=\(id.uuidString.prefix(8)) segments=\(transcript.segments.count)")
    Self.writer.async {
      do { try Self.database(in: self.folder).replace(id, transcript: transcript) } catch {
        self.fail(error)
      }
    }
  }

  func append(_ segments: [TranscriptSegment], until: Double) {
    guard let id = selected.withLock({ $0 }) else { return }
    Self.writer.async {
      do { try Self.database(in: self.folder).append(id, segments: segments, until: until) } catch {
        self.fail(error)
      }
    }
  }

  func replaceSegments(_ segments: [TranscriptSegment]) {
    guard let id = selected.withLock({ $0 }) else { return }
    Self.writer.async {
      do {
        let store = try Self.database(in: self.folder)
        guard var transcript = try store.load(id) else { return }
        transcript.segments = segments
        try store.replace(id, transcript: transcript)
      } catch { self.fail(error) }
    }
  }

  func finish(duration: Double, complete: Bool) {
    guard
      let id = selected.withLock({ current -> UUID? in
        defer { current = nil }
        return current
      })
    else { return }
    DiagnosticLog.shared.event(
      "history-meeting", "finish_queued",
      "id=\(id.uuidString.prefix(8)) duration=\(Int(duration)) complete=\(complete)")
    Self.writer.async {
      do {
        try Self.database(in: self.folder).finish(id, duration: duration, complete: complete)
        DispatchQueue.main.async {
          NotificationCenter.default.post(name: .recordingStoreDidChange, object: nil)
        }
      } catch { self.fail(error) }
    }
  }

  func flush() {
    Self.writer.sync {}
    DiagnosticLog.shared.event("history-meeting", "queue_flushed")
  }

  private func fail(_ error: Error) {
    DiagnosticLog.shared.event(
      "history-meeting", "autosave_failed", "error_type=\(type(of: error))")
    DispatchQueue.main.async {
      self.onError(error)
    }
  }

  func saved(retentionDays: Int, now: Date) throws -> [SavedMeeting] {
    flush()
    let store = try Self.database(in: folder)
    try store.prune(retentionDays: retentionDays, now: now)
    return try store.list(category: .meeting).compactMap { summary in
      guard let transcript = try store.load(summary.id) else { return nil }
      return SavedMeeting(id: summary.id, transcript: transcript, date: summary.createdAt)
    }
  }

  func read(_ id: UUID) throws -> FileTranscript? {
    flush()
    return try Self.database(in: folder).load(id)
  }

  @discardableResult
  func save(_ transcript: FileTranscript, to id: UUID? = nil) throws -> UUID {
    flush()
    let store = try Self.database(in: folder)
    if let id {
      try store.replace(id, transcript: transcript)
      return id
    }
    return try store.create(transcript, category: .meeting, date: transcript.startedAt ?? Date())
  }

  func delete(_ id: UUID) throws {
    flush()
    try Self.database(in: folder).delete(id)
  }

  func deleteAll() throws {
    flush()
    try Self.database(in: folder).deleteAll(category: .meeting)
  }
}

extension Notification.Name {
  static let recordingStoreDidChange = Notification.Name("app.dictlocalai.recordings.changed")
}
