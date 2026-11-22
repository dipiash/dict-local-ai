import Combine
import DictApplication
import DictCore
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
  @Published private(set) var entries: [RecordingSummary] = []
  @Published private(set) var error: String?
  @Published private var draft = HistoryDraft()
  var draftID: UUID? { draft.id }
  var draftDocument: FileTranscript? { draft.document }
  var draftDirty: Bool { draft.isDirty }

  func selectDraft(_ id: UUID?) {
    guard !draft.isDirty else { return }
    draft = HistoryDraft(id: id, document: id.flatMap { load($0) })
    DiagnosticLog.shared.event("history-ui", "draft_selected", "has_selection=\(id != nil)")
  }

  func renameDraftSpeaker(_ id: String, name: String) {
    draft.renameSpeaker(id, name: name)
  }

  func editDraftSegment(_ index: Int, text: String) {
    draft.editSegment(index, text: text)
  }

  @discardableResult func saveDraft() -> Bool {
    guard draft.isDirty else { return true }
    do {
      guard try history.saveDraft(draft) else { return false }
      draft.markSaved()
      reload()
      DiagnosticLog.shared.event("history-ui", "draft_saved")
      return true
    } catch {
      DiagnosticLog.shared.event("history", "update_failed", "error_type=\(type(of: error))")
      self.error = L10n.text("history.could-not-save-changes", L10n.error(error))
      return false
    }
  }

  func discardDraft() {
    let id = draft.id
    draft = HistoryDraft()
    selectDraft(id)
    DiagnosticLog.shared.event("history-ui", "draft_discarded")
  }

  private let history: RecordingHistory

  init(history: RecordingHistory) {
    self.history = history
    reload()
  }

  func reload() {
    do {
      entries = try history.recent()
      error = nil
      DiagnosticLog.shared.event("history", "reload", "count=\(entries.count)")
    } catch {
      DiagnosticLog.shared.event("history", "reload_failed", "error_type=\(type(of: error))")
      self.error = L10n.text("history.could-not-read-history", L10n.error(error))
    }
  }

  func reportSaveFailure(_ error: Error, category: RecordingCategory) {
    DiagnosticLog.shared.event(
      "history", "save_failed", "category=\(category.rawValue) error_type=\(type(of: error))")
    self.error = L10n.text("history.could-not-save-the-record", L10n.error(error))
  }

  func load(_ id: UUID) -> FileTranscript? {
    do {
      let result = try history.load(id)
      error = nil
      return result
    } catch {
      DiagnosticLog.shared.event("history", "load_failed", "error_type=\(type(of: error))")
      self.error = L10n.text("history.could-not-open-the-record", L10n.error(error))
      return nil
    }
  }

  func delete(_ id: UUID) {
    do {
      try history.delete(id)
      reload()
    } catch {
      DiagnosticLog.shared.event("history", "delete_failed", "error_type=\(type(of: error))")
      self.error = L10n.text("history.could-not-delete-the-record", L10n.error(error))
    }
  }

  func clear(category: RecordingCategory? = nil) {
    do {
      try history.clear(category: category)
      reload()
    } catch {
      DiagnosticLog.shared.event("history", "clear_failed", "error_type=\(type(of: error))")
      self.error = L10n.text("history.could-not-clear-history", L10n.error(error))
    }
  }

  func prune() { reload() }
}
