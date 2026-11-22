import Foundation

public struct HistoryDraft {
  public private(set) var id: UUID?
  public private(set) var document: FileTranscript?
  public private(set) var isDirty = false

  public init(id: UUID? = nil, document: FileTranscript? = nil) {
    self.id = id
    self.document = document
  }

  public mutating func renameSpeaker(_ id: String, name: String) {
    guard document != nil else { return }
    document?.speakerNames[id] = name
    isDirty = true
  }

  public mutating func editSegment(_ index: Int, text: String) {
    if document?.editSegmentText(at: index, text: text) == true { isDirty = true }
  }

  public mutating func markSaved() { isDirty = false }
}
