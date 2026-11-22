import AppKit
import Combine

@MainActor
final class ShortcutCapture: ObservableObject {
  @Published var active: String?
  private var monitor: Any?
  private var candidate: Shortcut?
  private weak var hotkeys: Hotkeys?
  func begin(_ name: String, hotkeys: Hotkeys, completion: @escaping (Shortcut) -> Void) {
    cancel()
    self.hotkeys = hotkeys
    hotkeys.reset()
    hotkeys.capturing = true
    active = name
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
      [weak self] event in
      guard let self else { return event }
      if event.type == .keyDown, event.keyCode == 12, event.modifierFlags.contains(.command) {
        self.cancel()
        return event
      }
      if event.type == .keyDown, event.keyCode == 53 {
        self.cancel()
        return nil
      }
      if event.type == .flagsChanged, let flag = Shortcut.modifierKeys[event.keyCode] {
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(
          Shortcut.mask)
        if flags.contains(flag) {
          self.candidate = self.shortcut(event, flags: flags.subtracting(flag))
        } else if let candidate = self.candidate, candidate.key == event.keyCode {
          completion(candidate)
          self.cancel()
        }
        return nil
      }
      if event.type == .keyDown {
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(
          Shortcut.mask)
        guard !flags.isEmpty || (122...135).contains(event.keyCode) else { return nil }
        completion(self.shortcut(event, flags: flags))
        self.cancel()
        return nil
      }
      return event
    }
  }
  private func shortcut(_ event: NSEvent, flags: CGEventFlags) -> Shortcut {
    var parts: [String] = []
    for (flag, label): (CGEventFlags, String) in [
      (.maskControl, "⌃"), (.maskAlternate, "⌥"),
      (.maskShift, "⇧"), (.maskCommand, "⌘"), (.maskSecondaryFn, "Fn"),
    ] {
      if flags.contains(flag) { parts.append(label) }
    }
    let key = event.keyCode
    let names: [UInt16: String] = [63: "Fn", 49: "Space"]
    parts.append(
      names[key] ?? Shortcut.nameForModifierKey(key)
        ?? event.charactersIgnoringModifiers?.uppercased()
        ?? L10n.text("shortcuts.key", String(key)))
    return Shortcut(
      key: event.keyCode, modifiers: flags.rawValue, label: parts.joined(separator: " + "))
  }
  func cancel() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    active = nil
    candidate = nil
    hotkeys?.capturing = false
  }

}
