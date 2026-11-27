import AppKit
import ApplicationServices
import DictApplication
import DictCore

struct InsertionTarget {
  let pid: pid_t
  let window: AXUIElement?
}

@MainActor
enum TextInsertion {
  // Target apps read the clipboard some time after Cmd+V; 0.8 s covers slow Electron apps.
  private static let clipboardRestorer = ClipboardPreserver(
    board: .general, delay: .milliseconds(800))

  private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else {
      return nil
    }
    return value
  }

  private static func axElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
  }

  private static func focusedContext(pid: pid_t) -> (window: AXUIElement?, secure: Bool) {
    let application = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(application, 0.25)
    let window = axElement(attribute(application, kAXFocusedWindowAttribute))
    var element = axElement(attribute(application, kAXFocusedUIElementAttribute))
    var seen: [AXUIElement] = []
    for _ in 0..<6 {
      guard let current = element, !seen.contains(where: { CFEqual($0, current) }) else {
        break
      }
      AXUIElementSetMessagingTimeout(current, 0.25)
      seen.append(current)
      if attribute(current, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole {
        return (window, true)
      }
      element = axElement(attribute(current, kAXParentAttribute))
    }
    return (window, false)
  }

  static func target() -> InsertionTarget? {
    guard AXIsProcessTrusted() else {
      DiagnosticLog.shared.event("insertion", "target_unavailable", "reason=accessibility")
      return nil
    }
    guard let app = NSWorkspace.shared.frontmostApplication else {
      DiagnosticLog.shared.event("insertion", "target_unavailable", "reason=no_frontmost_app")
      return nil
    }
    let context = focusedContext(pid: app.processIdentifier)
    guard !context.secure else {
      DiagnosticLog.shared.event("insertion", "target_unavailable", "reason=secure_input")
      return nil
    }
    DiagnosticLog.shared.event(
      "insertion", "target_captured",
      "pid=\(app.processIdentifier) window=\(context.window == nil ? "unknown" : "known")")
    return InsertionTarget(pid: app.processIdentifier, window: context.window)
  }

  static func matches(_ expected: InsertionTarget) -> Bool {
    guard let frontmost = NSWorkspace.shared.frontmostApplication else {
      DiagnosticLog.shared.event("insertion", "target_recheck_failed", "reason=no_frontmost_app")
      return false
    }
    let context = focusedContext(pid: frontmost.processIdentifier)
    let bothWindowsKnown = expected.window != nil && context.window != nil
    let sameWindow: Bool
    if let expectedWindow = expected.window, let currentWindow = context.window {
      sameWindow = CFEqual(expectedWindow, currentWindow)
    } else {
      sameWindow = false
    }
    let accepted = TextInsertionPolicy.mayPaste(
      sameProcess: frontmost.processIdentifier == expected.pid,
      sameWindow: sameWindow,
      bothWindowsKnown: bothWindowsKnown,
      secure: context.secure)
    if !accepted {
      DiagnosticLog.shared.event(
        "insertion", "target_recheck_failed",
        "reason=changed_app_window_or_secure sameProcess=\(frontmost.processIdentifier == expected.pid) "
          + "sameWindow=\(sameWindow) secure=\(context.secure)")
    }
    return accepted
  }

  static func insertInFocusedLocalEditor(_ text: String) -> Bool {
    guard NSApp.isActive, let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
      editor.isEditable
    else { return false }
    editor.insertText(text, replacementRange: editor.selectedRange())
    DiagnosticLog.shared.event("insertion", "local_editor_inserted", "chars=\(text.count)")
    return true
  }

  @discardableResult static func copy(_ text: String) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
  }

  // Cmd+V has no delivery receipt, so a retry can paste twice.
  private static func postShortUnicode(_ text: String, target: InsertionTarget) -> Bool {
    let units = Array(text.utf16)
    guard !units.isEmpty, units.count <= 256,
      let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false),
      matches(target)
    else { return false }
    units.withUnsafeBufferPointer { buffer in
      down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
      up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
    }
    for event in [down, up] {
      event.setIntegerValueField(.eventSourceUserData, value: ShortcutEvent.appEventTag)
      event.post(tap: .cghidEventTap)
    }
    DiagnosticLog.shared.event("insertion", "unicode_posted_unconfirmed", "chars=\(text.count)")
    return true
  }

  static func pasteKeyEvents() -> [CGEvent]? {
    let leftCommand: CGKeyCode = 55
    let v: CGKeyCode = 9
    guard
      let commandDown = CGEvent(keyboardEventSource: nil, virtualKey: leftCommand, keyDown: true),
      let vDown = CGEvent(keyboardEventSource: nil, virtualKey: v, keyDown: true),
      let vUp = CGEvent(keyboardEventSource: nil, virtualKey: v, keyDown: false),
      let commandUp = CGEvent(keyboardEventSource: nil, virtualKey: leftCommand, keyDown: false)
    else { return nil }
    commandDown.type = .flagsChanged
    commandDown.flags = .maskCommand
    vDown.flags = .maskCommand
    vUp.flags = .maskCommand
    commandUp.type = .flagsChanged
    commandUp.flags = []
    let events = [commandDown, vDown, vUp, commandUp]
    for event in events {
      event.setIntegerValueField(.eventSourceUserData, value: ShortcutEvent.appEventTag)
    }
    return events
  }

  static func insert(
    _ text: String, target: InsertionTarget?, restoreClipboard: Bool = true
  ) -> TextInsertionOutcome {
    guard let target else {
      DiagnosticLog.shared.event("insertion", "delivery_unavailable", "reason=no_completion_target")
      return .unavailable
    }
    guard matches(target) else {
      DiagnosticLog.shared.event("insertion", "delivery_unavailable", "reason=focus_changed")
      return .unavailable
    }
    if target.pid == ProcessInfo.processInfo.processIdentifier,
      insertInFocusedLocalEditor(text)
    {
      return .inserted
    }

    let previousClipboard = clipboardRestorer.prepare(enabled: restoreClipboard)
    guard copy(text) else {
      DiagnosticLog.shared.event("insertion", "delivery_unavailable", "reason=clipboard_write")
      return .unavailable
    }
    let board = NSPasteboard.general
    let copiedChange = board.changeCount
    guard matches(target), board.changeCount == copiedChange,
      board.string(forType: .string) == text
    else {
      DiagnosticLog.shared.event(
        "insertion", "delivery_unavailable", "reason=focus_or_clipboard_changed_before_paste")
      return .unavailable
    }
    guard let events = pasteKeyEvents() else {
      guard postShortUnicode(text, target: target) else { return .unavailable }
      clipboardRestorer.restoreAfterPaste(previousClipboard, pasteChangeCount: copiedChange)
      return .pasteRequested
    }
    // Chromium needs separate Command key events to receive this paste.
    for event in events { event.post(tap: .cghidEventTap) }
    DiagnosticLog.shared.event("insertion", "paste_posted_unconfirmed", "pid=\(target.pid)")
    clipboardRestorer.restoreAfterPaste(previousClipboard, pasteChangeCount: copiedChange)
    return .pasteRequested
  }
}
