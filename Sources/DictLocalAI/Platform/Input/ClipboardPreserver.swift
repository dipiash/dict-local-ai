import AppKit

struct ClipboardContents {
  struct Entry {
    let type: NSPasteboard.PasteboardType
    let data: Data
  }

  let items: [[Entry]]
}

enum ClipboardReadResult {
  case snapshot(ClipboardContents)
  case skipped(reason: String)
}

enum ClipboardRestoreResult: Equatable {
  case restored
  case skipped(reason: String)
}

enum ClipboardContentsReader {
  // Skip clipboard entries marked as concealed by password managers.
  static let privatePasteboardTypes: Set<NSPasteboard.PasteboardType> = [
    NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
    NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
  ]
  static let maxBytes = 64 * 1024 * 1024

  static func capture(_ board: NSPasteboard) -> ClipboardReadResult {
    let boardItems = board.pasteboardItems ?? []
    var total = 0
    var items: [[ClipboardContents.Entry]] = []
    for item in boardItems {
      if item.types.contains(where: privatePasteboardTypes.contains) {
        return .skipped(reason: "concealed_content")
      }
      var entries: [ClipboardContents.Entry] = []
      for type in item.types {
        guard let data = item.data(forType: type) else { continue }
        total += data.count
        if total > maxBytes { return .skipped(reason: "content_too_large") }
        entries.append(.init(type: type, data: data))
      }
      items.append(entries)
    }
    return .snapshot(ClipboardContents(items: items))
  }

  static func restore(
    _ snapshot: ClipboardContents, to board: NSPasteboard, expectedChangeCount: Int
  ) -> ClipboardRestoreResult {
    guard board.changeCount == expectedChangeCount else {
      return .skipped(reason: "clipboard_changed")
    }
    board.clearContents()
    let objects = snapshot.items.map { entries -> NSPasteboardItem in
      let item = NSPasteboardItem()
      for entry in entries { item.setData(entry.data, forType: entry.type) }
      return item
    }
    guard objects.isEmpty || board.writeObjects(objects) else {
      return .skipped(reason: "write_failed")
    }
    return .restored
  }
}

@MainActor
final class ClipboardPreserver {
  private struct Pending {
    let capture: ClipboardReadResult
    let changeCount: Int
    let task: Task<Void, Never>
  }

  private let board: NSPasteboard
  private let delay: Duration
  private var pending: Pending?

  init(board: NSPasteboard, delay: Duration) {
    self.board = board
    self.delay = delay
  }

  // Overlapping dictations should restore the clipboard contents from before either paste.
  func prepare(enabled: Bool = true) -> ClipboardReadResult {
    // Disabling restoration skips the snapshot and leaves the transcript on the clipboard.
    guard enabled else { return .skipped(reason: "disabled") }
    if let pending, board.changeCount == pending.changeCount { return pending.capture }
    return ClipboardContentsReader.capture(board)
  }

  func restoreAfterPaste(_ capture: ClipboardReadResult, pasteChangeCount: Int) {
    pending?.task.cancel()
    pending = nil
    guard case .snapshot(let snapshot) = capture else {
      if case .skipped(let reason) = capture { logSkipped(reason) }
      return
    }
    let task = Task { @MainActor [weak self] in
      try? await Task.sleep(for: self?.delay ?? .zero)
      guard !Task.isCancelled, let self else { return }
      self.pending = nil
      switch ClipboardContentsReader.restore(
        snapshot, to: self.board, expectedChangeCount: pasteChangeCount)
      {
      case .restored: DiagnosticLog.shared.event("insertion", "clipboard_restored", "")
      case .skipped(let reason): self.logSkipped(reason)
      }
    }
    pending = Pending(capture: capture, changeCount: pasteChangeCount, task: task)
  }

  private func logSkipped(_ reason: String) {
    DiagnosticLog.shared.event("insertion", "clipboard_restore_skipped", "reason=\(reason)")
  }
}
