import DictCore
import Foundation

public struct RecordingStorageError: LocalizedError, Sendable {
  public enum Kind: Sendable {
    case storage, missingRecord
  }

  public let kind: Kind
  public let message: String
  public let code: Int32?
  public init(message: String, code: Int32? = nil, kind: Kind = .storage) {
    self.kind = kind
    self.message = message
    self.code = code
  }
  public var errorDescription: String? { message }
}

public protocol RecordingWriter: Sendable {
  func create(
    _ transcript: FileTranscript, category: RecordingCategory, id: UUID, date: Date
  ) throws -> UUID
}

public protocol RecordingHistoryRepository: RecordingWriter {
  func load(_ id: UUID) throws -> FileTranscript?
  func list(category: RecordingCategory?) throws -> [RecordingSummary]
  func replace(_ id: UUID, transcript: FileTranscript) throws
  func delete(_ id: UUID) throws
  func deleteAll(category: RecordingCategory?) throws
  func prune(retentionDays: Int, now: Date) throws
}

public enum RecordingRetention {
  public static let days = 7
}

public struct RecordingHistory: Sendable {
  private let repository: @Sendable () throws -> any RecordingHistoryRepository

  public init(repository: @escaping @Sendable () throws -> any RecordingHistoryRepository) {
    self.repository = repository
  }

  public func recent(now: Date = Date()) throws -> [RecordingSummary] {
    let store = try repository()
    try store.prune(retentionDays: RecordingRetention.days, now: now)
    return try store.list(category: nil)
  }

  public func load(_ id: UUID) throws -> FileTranscript? {
    try repository().load(id)
  }

  public func saveDraft(_ draft: HistoryDraft) throws -> Bool {
    guard draft.isDirty, let id = draft.id, let document = draft.document else { return false }
    try repository().replace(id, transcript: document)
    return true
  }

  public func delete(_ id: UUID) throws {
    try repository().delete(id)
  }

  public func clear(category: RecordingCategory?) throws {
    try repository().deleteAll(category: category)
  }
}
