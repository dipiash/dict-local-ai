import AppKit

/// Classify the focused control in History.
enum HistoryKeyboardFocus: Equatable {
  case textInput
  case list
  case control
  case nothing
}

/// Decide when History handles arrow keys and clears editor focus.
enum HistoryKeyboardPolicy {
  /// A text field and a list use the arrows themselves. Any other focus, such as a clicked button or slider, leaves them to the panel.
  static func shouldSeekWithArrows(focus: HistoryKeyboardFocus, playing: Bool) -> Bool {
    playing && focus != .textInput && focus != .list
  }

  /// Clear editor focus when the user clicks a different control.
  static func shouldClearTextFocus(focus: HistoryKeyboardFocus, clickInTextInput: Bool) -> Bool {
    focus == .textInput && !clickInTextInput
  }

  static func focusTarget(of responder: NSResponder?, in window: NSWindow) -> HistoryKeyboardFocus {
    if responder is NSTextView || responder is NSTextField { return .textInput }
    if isInsideList(responder) { return .list }
    if responder == nil || responder === window || responder === window.contentView {
      return .nothing
    }
    return .control
  }

  private static func isInsideList(_ responder: NSResponder?) -> Bool {
    var current = responder as? NSView
    while let candidate = current {
      if candidate is NSTableView { return true }
      current = candidate.superview
    }
    return false
  }

  /// Log text of a click: only the focus and the class of the view, never text or file names.
  static func describeHistoryClick(focus: HistoryKeyboardFocus, hit: NSView?, released: Bool)
    -> String
  {
    "focus=\(focus) hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil") released=\(released)"
  }

  static func isTextInput(_ view: NSView?) -> Bool {
    var current = view
    while let candidate = current {
      if candidate is NSTextView || candidate is NSTextField { return true }
      current = candidate.superview
    }
    return false
  }
}

/// Route History window clicks and arrow-key events.
@MainActor
final class HistoryKeyboardMonitor {
  private var monitor: Any?
  /// Seconds to move per arrow press.
  private let step: Double

  init(step: Double = 5) { self.step = step }

  /// `playing` says whether a record plays; `jump` gets the signed seconds.
  func start(playing: @escaping () -> Bool, jump: @escaping (Double) -> Void) {
    stop()
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) {
      [step] event in
      guard let window = event.window else { return event }
      let focus = HistoryKeyboardPolicy.focusTarget(of: window.firstResponder, in: window)
      if event.type == .leftMouseDown {
        let hit = window.contentView?.hitTest(event.locationInWindow)
        let released = HistoryKeyboardPolicy.shouldClearTextFocus(
          focus: focus, clickInTextInput: HistoryKeyboardPolicy.isTextInput(hit))
        if released { window.makeFirstResponder(nil) }
        DiagnosticLog.shared.event(
          "history-ui", "click",
          HistoryKeyboardPolicy.describeHistoryClick(focus: focus, hit: hit, released: released))
        return event
      }
      let isPlaying = playing()
      let owns = HistoryKeyboardPolicy.shouldSeekWithArrows(focus: focus, playing: isPlaying)
      if event.keyCode == 123 || event.keyCode == 124 {
        DiagnosticLog.shared.event(
          "history-ui", "arrow_key",
          "focus=\(focus) responder=\(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil") playing=\(isPlaying) handled=\(owns)"
        )
      }
      guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty, owns
      else { return event }
      switch event.keyCode {
      case 123:
        jump(-step)
        return nil
      case 124:
        jump(step)
        return nil
      default: return event
      }
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}
