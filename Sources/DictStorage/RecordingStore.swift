import CSQLite
import DictApplication
import DictCore
import Foundation

public final class RecordingStore: RecordingHistoryRepository, @unchecked Sendable {
  private let lock = NSRecursiveLock()
  private let onEvent: @Sendable (String, String) -> Void

  // Keep text and file paths out of storage logs.
  private func traced<T>(_ operation: String, _ details: String, body: () throws -> T) throws -> T {
    let start = ProcessInfo.processInfo.systemUptime
    do {
      let result = try body()
      let millis = Int((ProcessInfo.processInfo.systemUptime - start) * 1_000)
      onEvent(operation + "_ok", "\(details) ms=\(millis)")
      return result
    } catch {
      let millis = Int((ProcessInfo.processInfo.systemUptime - start) * 1_000)
      let code =
        (error as? RecordingStorageError)?.code
        ?? database.map { sqlite3_extended_errcode($0) } ?? -1
      onEvent(
        operation + "_failed",
        "\(details) ms=\(millis) sqlite_code=\(code) error_type=\(type(of: error))")
      throw error
    }
  }

  private var database: OpaquePointer?
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(
    url: URL,
    onEvent: @escaping @Sendable (String, String) -> Void = { _, _ in }
  ) throws {
    self.onEvent = onEvent
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    var pointer: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(url.path, &pointer, flags, nil) == SQLITE_OK, let pointer else {
      let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
      sqlite3_close(pointer)
      throw RecordingStorageError(message: "Could not open the recording database: \(message)")
    }
    database = pointer
    do {
      try execute("PRAGMA foreign_keys=ON")
      try execute("PRAGMA busy_timeout=5000")
      try execute("PRAGMA journal_mode=WAL")
      try execute("PRAGMA synchronous=FULL")
      try execute(
        """
        CREATE TABLE IF NOT EXISTS recordings (
          id TEXT PRIMARY KEY,
          category TEXT NOT NULL CHECK(category IN ('dictation','meeting','file')),
          title TEXT NOT NULL,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          duration REAL NOT NULL DEFAULT 0,
          processed_until REAL NOT NULL DEFAULT 0,
          complete INTEGER NOT NULL DEFAULT 0,
          preview TEXT NOT NULL DEFAULT '',
          meta BLOB NOT NULL
        )
        """)
      try execute(
        """
        CREATE TABLE IF NOT EXISTS recording_segments (
          recording_id TEXT NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
          seq INTEGER NOT NULL,
          start REAL NOT NULL,
          end REAL NOT NULL,
          text TEXT NOT NULL,
          speaker_id TEXT,
          channel TEXT,
          PRIMARY KEY(recording_id, seq)
        )
        """)
      try execute(
        "CREATE INDEX IF NOT EXISTS idx_recording_kind_date ON recordings(category,created_at DESC)"
      )
      try execute("CREATE INDEX IF NOT EXISTS idx_recording_date ON recordings(created_at DESC)")
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      onEvent("open_ok", "schema=1 wal=true")
    } catch {
      onEvent(
        "open_failed",
        "error_type=\(type(of: error)) sqlite_code=\(sqlite3_extended_errcode(pointer))")
      sqlite3_close(pointer)
      database = nil
      throw error
    }
  }

  deinit {
    lock.lock()
    if let database { sqlite3_close(database) }
    lock.unlock()
  }

  private func fail(_ context: String) -> RecordingStorageError {
    RecordingStorageError(
      message:
        "SQLite \(context): \(database.map { String(cString: sqlite3_errmsg($0)) } ?? "closed")",
      code: database.map { sqlite3_extended_errcode($0) })
  }

  private func execute(_ sql: String) throws {
    guard let database, sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
      throw fail("execute")
    }
  }

  private func statement(_ sql: String) throws -> OpaquePointer {
    var stmt: OpaquePointer?
    guard let database, sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK,
      let stmt
    else { throw fail("prepare") }
    return stmt
  }

  private func text(_ value: String, at index: Int32, in stmt: OpaquePointer) {
    _ = value.withCString { sqlite3_bind_text(stmt, index, $0, -1, Self.transient) }
  }

  private func blob(_ data: Data, at index: Int32, in stmt: OpaquePointer) {
    _ = data.withUnsafeBytes { bytes in
      sqlite3_bind_blob(stmt, index, bytes.baseAddress, Int32(bytes.count), Self.transient)
    }
  }

  private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String {
    guard let bytes = sqlite3_column_text(stmt, index) else { return "" }
    return String(cString: bytes)
  }

  private func columnData(_ stmt: OpaquePointer, _ index: Int32) -> Data {
    let count = Int(sqlite3_column_bytes(stmt, index))
    guard count > 0, let bytes = sqlite3_column_blob(stmt, index) else { return Data() }
    return Data(bytes: bytes, count: count)
  }

  private func changed(_ stmt: OpaquePointer) throws {
    guard sqlite3_step(stmt) == SQLITE_DONE else { throw fail("write") }
  }

  private func transactional<T>(_ operation: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE")
    do {
      let result = try operation()
      try execute("COMMIT")
      return result
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  public func create(
    _ transcript: FileTranscript, category: RecordingCategory, id: UUID = UUID(),
    date: Date = Date()
  ) throws -> UUID {
    return try traced(
      "create",
      "category=\(category.rawValue) id=\(id.uuidString.prefix(8)) segments=\(transcript.segments.count)"
    ) {
      lock.lock()
      defer { lock.unlock() }
      try transactional {
        let stmt = try statement(
          """
          INSERT INTO recordings
          (id,category,title,created_at,updated_at,duration,processed_until,complete,preview,meta)
          VALUES (?,?,?,?,?,?,?,?,?,?)
          """)
        defer { sqlite3_finalize(stmt) }
        text(id.uuidString, at: 1, in: stmt)
        text(category.rawValue, at: 2, in: stmt)
        text(transcript.source, at: 3, in: stmt)
        sqlite3_bind_double(stmt, 4, date.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 5, date.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 6, transcript.duration)
        sqlite3_bind_double(stmt, 7, transcript.processedUntil)
        sqlite3_bind_int(stmt, 8, transcript.complete ? 1 : 0)
        text(
          String(transcript.segments.map(\.text).joined(separator: " ").prefix(240)), at: 9,
          in: stmt)
        var meta = transcript
        meta.segments = []
        blob(try encoder.encode(meta), at: 10, in: stmt)
        try changed(stmt)
        try addSegments(id, transcript.segments, offset: 0)
      }
      return id

    }
  }

  private func addSegments(_ id: UUID, _ segments: [TranscriptSegment], offset: Int) throws {
    guard !segments.isEmpty else { return }
    let stmt = try statement(
      """
      INSERT INTO recording_segments
      (recording_id,seq,start,end,text,speaker_id,channel) VALUES (?,?,?,?,?,?,?)
      """)
    defer { sqlite3_finalize(stmt) }
    for (index, segment) in segments.enumerated() {
      sqlite3_reset(stmt)
      sqlite3_clear_bindings(stmt)
      text(id.uuidString, at: 1, in: stmt)
      sqlite3_bind_int64(stmt, 2, Int64(offset + index))
      sqlite3_bind_double(stmt, 3, segment.start)
      sqlite3_bind_double(stmt, 4, segment.end)
      text(segment.text, at: 5, in: stmt)
      if let speaker = segment.speakerID { text(speaker, at: 6, in: stmt) }
      if let channel = segment.channel { text(channel, at: 7, in: stmt) }
      try changed(stmt)
    }
  }

  public func append(_ id: UUID, segments: [TranscriptSegment], until: Double) throws {
    try traced(
      "append", "id=\(id.uuidString.prefix(8)) segments=\(segments.count) until=\(Int(until))"
    ) {
      lock.lock()
      defer { lock.unlock() }
      try transactional {
        let count = try statement(
          "SELECT COALESCE(MAX(seq)+1, 0) FROM recording_segments WHERE recording_id=?")
        text(id.uuidString, at: 1, in: count)
        guard sqlite3_step(count) == SQLITE_ROW else {
          sqlite3_finalize(count)
          throw fail("count")
        }
        let offset = Int(sqlite3_column_int64(count, 0))
        sqlite3_finalize(count)
        try addSegments(id, segments, offset: offset)
        let update = try statement(
          """
          UPDATE recordings SET updated_at=?, processed_until=MAX(processed_until,?),
            duration=MAX(duration,?), preview=CASE WHEN preview='' THEN ? ELSE preview END
          WHERE id=?
          """)
        defer { sqlite3_finalize(update) }
        sqlite3_bind_double(update, 1, Date().timeIntervalSince1970)
        sqlite3_bind_double(update, 2, until)
        sqlite3_bind_double(update, 3, until)
        text(String(segments.map(\.text).joined(separator: " ").prefix(240)), at: 4, in: update)
        text(id.uuidString, at: 5, in: update)
        try changed(update)
      }

    }
  }

  public func replace(_ id: UUID, transcript: FileTranscript) throws {
    try traced("replace", "id=\(id.uuidString.prefix(8)) segments=\(transcript.segments.count)") {
      lock.lock()
      defer { lock.unlock() }
      try transactional {
        var meta = transcript
        meta.segments = []
        let update = try statement(
          """
          UPDATE recordings SET title=?,updated_at=?,duration=?,processed_until=?,
            complete=?,preview=?,meta=? WHERE id=?
          """)
        defer { sqlite3_finalize(update) }
        text(transcript.source, at: 1, in: update)
        sqlite3_bind_double(update, 2, Date().timeIntervalSince1970)
        sqlite3_bind_double(update, 3, transcript.duration)
        sqlite3_bind_double(update, 4, transcript.processedUntil)
        sqlite3_bind_int(update, 5, transcript.complete ? 1 : 0)
        text(
          String(transcript.segments.map(\.text).joined(separator: " ").prefix(240)), at: 6,
          in: update)
        blob(try encoder.encode(meta), at: 7, in: update)
        text(id.uuidString, at: 8, in: update)
        try changed(update)
        guard sqlite3_changes(database) > 0 else {
          throw RecordingStorageError(message: "Recording not found: \(id)", kind: .missingRecord)
        }
        let remove = try statement("DELETE FROM recording_segments WHERE recording_id=?")
        text(id.uuidString, at: 1, in: remove)
        defer { sqlite3_finalize(remove) }
        try changed(remove)
        try addSegments(id, transcript.segments, offset: 0)
      }

    }
  }

  public func finish(_ id: UUID, duration: Double, complete: Bool) throws {
    try traced(
      "finish", "id=\(id.uuidString.prefix(8)) complete=\(complete) duration=\(Int(duration))"
    ) {
      lock.lock()
      defer { lock.unlock() }
      try transactional {
        let read = try statement("SELECT meta FROM recordings WHERE id=?")
        text(id.uuidString, at: 1, in: read)
        guard sqlite3_step(read) == SQLITE_ROW else {
          sqlite3_finalize(read)
          throw RecordingStorageError(message: "Recording not found: \(id)", kind: .missingRecord)
        }
        var meta = try decoder.decode(FileTranscript.self, from: columnData(read, 0))
        sqlite3_finalize(read)
        meta.duration = max(duration, meta.duration)
        meta.complete = complete
        let update = try statement(
          """
          UPDATE recordings SET duration=MAX(duration,?),complete=?,updated_at=?,meta=? WHERE id=?
          """)
        defer { sqlite3_finalize(update) }
        sqlite3_bind_double(update, 1, duration)
        sqlite3_bind_int(update, 2, complete ? 1 : 0)
        sqlite3_bind_double(update, 3, Date().timeIntervalSince1970)
        blob(try encoder.encode(meta), at: 4, in: update)
        text(id.uuidString, at: 5, in: update)
        try changed(update)
      }

    }
  }

  public func load(_ id: UUID) throws -> FileTranscript? {
    return try traced("load", "id=\(id.uuidString.prefix(8))") {
      lock.lock()
      defer { lock.unlock() }
      let stmt = try statement(
        "SELECT meta,duration,processed_until,complete FROM recordings WHERE id=?")
      defer { sqlite3_finalize(stmt) }
      text(id.uuidString, at: 1, in: stmt)
      guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
      var transcript = try decoder.decode(FileTranscript.self, from: columnData(stmt, 0))
      transcript.duration = sqlite3_column_double(stmt, 1)
      transcript.processedUntil = sqlite3_column_double(stmt, 2)
      transcript.complete = sqlite3_column_int(stmt, 3) != 0
      let segments = try statement(
        """
        SELECT start,end,text,speaker_id,channel FROM recording_segments
        WHERE recording_id=? ORDER BY seq
        """)
      defer { sqlite3_finalize(segments) }
      text(id.uuidString, at: 1, in: segments)
      while sqlite3_step(segments) == SQLITE_ROW {
        let speaker =
          sqlite3_column_type(segments, 3) == SQLITE_NULL ? nil : columnText(segments, 3)
        let channel =
          sqlite3_column_type(segments, 4) == SQLITE_NULL ? nil : columnText(segments, 4)
        transcript.segments.append(
          TranscriptSegment(
            start: sqlite3_column_double(segments, 0), end: sqlite3_column_double(segments, 1),
            text: columnText(segments, 2), speakerID: speaker, channel: channel))
      }
      return transcript

    }
  }

  public func list(category: RecordingCategory? = nil) throws -> [RecordingSummary] {
    return try traced("list", "category=\(category?.rawValue ?? "all")") {
      lock.lock()
      defer { lock.unlock() }
      let sql = """
        SELECT r.id,r.category,r.title,r.created_at,r.duration,r.preview,r.complete,
               (SELECT COUNT(*) FROM recording_segments s WHERE s.recording_id=r.id)
        FROM recordings r \(category == nil ? "" : "WHERE r.category=?")
        ORDER BY r.created_at DESC
        """
      let stmt = try statement(sql)
      defer { sqlite3_finalize(stmt) }
      if let category { text(category.rawValue, at: 1, in: stmt) }
      var result: [RecordingSummary] = []
      while sqlite3_step(stmt) == SQLITE_ROW {
        guard let id = UUID(uuidString: columnText(stmt, 0)),
          let kind = RecordingCategory(rawValue: columnText(stmt, 1))
        else { continue }
        result.append(
          RecordingSummary(
            id: id, category: kind, title: columnText(stmt, 2),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
            duration: sqlite3_column_double(stmt, 4), preview: columnText(stmt, 5),
            segmentCount: Int(sqlite3_column_int(stmt, 7)),
            complete: sqlite3_column_int(stmt, 6) != 0))
      }
      return result

    }
  }

  public func delete(_ id: UUID) throws {
    try traced("delete", "id=\(id.uuidString.prefix(8))") {
      lock.lock()
      defer { lock.unlock() }
      let stmt = try statement("DELETE FROM recordings WHERE id=?")
      defer { sqlite3_finalize(stmt) }
      text(id.uuidString, at: 1, in: stmt)
      try changed(stmt)

    }
  }

  public func deleteAll(category: RecordingCategory? = nil) throws {
    try traced("deleteAll", "category=\(category?.rawValue ?? "all")") {
      lock.lock()
      defer { lock.unlock() }
      if let category {
        let stmt = try statement("DELETE FROM recordings WHERE category=?")
        defer { sqlite3_finalize(stmt) }
        text(category.rawValue, at: 1, in: stmt)
        try changed(stmt)
      } else {
        try execute("DELETE FROM recordings")
      }

    }
  }

  public func prune(retentionDays: Int, now: Date = Date()) throws {
    try traced("prune", "days=\(retentionDays)") {
      lock.lock()
      defer { lock.unlock() }
      let stmt = try statement("DELETE FROM recordings WHERE created_at < ?")
      defer { sqlite3_finalize(stmt) }
      sqlite3_bind_double(
        stmt, 1, now.addingTimeInterval(-Double(retentionDays) * 86_400).timeIntervalSince1970)
      try changed(stmt)

    }
  }
}
