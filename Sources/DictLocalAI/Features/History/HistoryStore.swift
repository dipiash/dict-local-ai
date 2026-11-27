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
  let audio: HistoryPlaybackController
  private var playbackStateSubscription: AnyCancellable?

  // Keep the original record snapshot to detect changes after opening the draft.
  private var loadedDraftDocument: FileTranscript?
  private var loadedRecordSummary: RecordingSummary?
  // After our own save the list entry differs from the base, and that is not a foreign change.
  private var acceptNextRecordSummary = false

  func selectDraft(_ id: UUID?) {
    guard !draft.isDirty else { return }
    openDraft(id)
    DiagnosticLog.shared.event("history-ui", "draft_selected", "has_selection=\(id != nil)")
  }

  private func openDraft(_ id: UUID?) {
    let document = id.flatMap { load($0) }
    draft = HistoryDraft(id: id, document: document)
    loadedDraftDocument = document
    loadedRecordSummary = entries.first { $0.id == id }
    acceptNextRecordSummary = false
  }

  // A meeting that ends or grows after it was opened must not be replaced by the old snapshot.
  private func reloadDraftIfStale() {
    guard let id = draft.id, let summary = entries.first(where: { $0.id == id }) else { return }
    guard !acceptNextRecordSummary, let loadedRecordSummary else {
      loadedRecordSummary = summary
      acceptNextRecordSummary = false
      return
    }
    guard summary != loadedRecordSummary, !draft.isDirty else { return }
    openDraft(id)
    DiagnosticLog.shared.event("history", "draft_refreshed", "reason=record_changed")
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
      // Reject a stale draft because saving it would overwrite content added to the record.
      if let id = draft.id, try history.load(id) != loadedDraftDocument {
        DiagnosticLog.shared.event("history", "draft_save_blocked", "reason=record_changed")
        fail(.draft, L10n.text("history.record-changed-while-open"))
        return false
      }
      guard try history.saveDraft(draft) else { return false }
      draft.markSaved()
      loadedDraftDocument = draft.document
      acceptNextRecordSummary = true
      clearActionFailure(.draft)
      reload()
      DiagnosticLog.shared.event("history-ui", "draft_saved")
      return true
    } catch {
      DiagnosticLog.shared.event("history", "update_failed", "error_type=\(type(of: error))")
      fail(.draft, L10n.text("history.could-not-save-changes", L10n.error(error)))
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

  init(history: RecordingHistory, audio: HistoryPlaybackController = HistoryPlaybackController()) {
    self.history = history
    self.audio = audio
    // The slider observes position updates. Redraw the list only when playback starts or stops.
    playbackStateSubscription = audio.$playingRecordID.removeDuplicates().dropFirst()
      .sink { [weak self] _ in self?.objectWillChange.send() }
    reload()
  }

  private var historyLoadRevision = 0
  // A successful reload clears its read error. Save and delete failures are tracked separately.
  private var historyReadFailure: String?
  // Clear an operation's failure once that operation succeeds.
  private enum FailureSource { case draft, save, delete, clear }
  private var operationFailure: (source: FailureSource, message: String)?

  private func fail(_ source: FailureSource, _ message: String) {
    error = message
    operationFailure = (source, message)
  }

  private func clearActionFailure(_ source: FailureSource) {
    guard let failure = operationFailure, failure.source == source else { return }
    if error == failure.message { error = nil }
    operationFailure = nil
  }

  // SQLite reads and audio pruning stalled the main thread for up to 2.4 s.
  func reload() {
    historyLoadRevision += 1
    let current = historyLoadRevision
    let history = history
    Task {
      let result = await Task.detached(priority: .userInitiated) {
        Result { try history.recent() }
      }.value
      guard current == historyLoadRevision else { return }
      switch result {
      case .success(let recent):
        entries = recent
        reloadDraftIfStale()
        if error == historyReadFailure { error = nil }
        historyReadFailure = nil
        DiagnosticLog.shared.event("history", "reload", "count=\(recent.count)")
      case .failure(let error):
        DiagnosticLog.shared.event("history", "reload_failed", "error_type=\(type(of: error))")
        let message = L10n.text("history.could-not-read-history", L10n.error(error))
        historyReadFailure = message
        self.error = message
      }
    }
  }

  func reportSaveFailure(_ error: Error, category: RecordingCategory) {
    DiagnosticLog.shared.event(
      "history", "save_failed", "category=\(category.rawValue) error_type=\(type(of: error))")
    fail(.save, L10n.text("history.could-not-save-the-record", L10n.error(error)))
  }

  func didSaveHistory() {
    clearActionFailure(.save)
    reload()
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
      clearActionFailure(.delete)
      reload()
    } catch {
      DiagnosticLog.shared.event("history", "delete_failed", "error_type=\(type(of: error))")
      fail(.delete, L10n.text("history.could-not-delete-the-record", L10n.error(error)))
    }
  }

  func clear(category: RecordingCategory? = nil) {
    do {
      try history.clear(category: category)
      clearActionFailure(.clear)
      reload()
    } catch {
      DiagnosticLog.shared.event("history", "clear_failed", "error_type=\(type(of: error))")
      fail(.clear, L10n.text("history.could-not-clear-history", L10n.error(error)))
    }
  }

  func prune() { reload() }
}
