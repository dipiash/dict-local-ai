import Foundation

public enum RecordingCategory: String, Codable, CaseIterable, Sendable {
  case dictation, meeting, file
}

public struct RecordingSummary: Identifiable, Sendable, Equatable {
  public let id: UUID
  public let category: RecordingCategory
  public let title: String
  public let createdAt: Date
  public let duration: Double
  public let preview: String
  public let segmentCount: Int
  public let complete: Bool

  public init(
    id: UUID, category: RecordingCategory, title: String, createdAt: Date, duration: Double,
    preview: String, segmentCount: Int, complete: Bool
  ) {
    self.id = id
    self.category = category
    self.title = title
    self.createdAt = createdAt
    self.duration = duration
    self.preview = preview
    self.segmentCount = segmentCount
    self.complete = complete
  }
}
