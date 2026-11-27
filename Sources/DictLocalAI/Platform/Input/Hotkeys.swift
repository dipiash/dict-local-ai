import AppKit

@MainActor
final class Hotkeys {
  var hold = Shortcut.hold {
    didSet { decider.configure { $0.hold = hold } }
  }
  var toggle = Shortcut.toggle {
    didSet { decider.configure { $0.toggle = toggle } }
  }
  var enabled = true {
    didSet { decider.configure { $0.enabled = enabled } }
  }
  var capturing = false {
    didSet { decider.configure { $0.capturing = capturing } }
  }
  var isApplicationActive: () -> Bool = { NSApp?.isActive == true }
  var isBusy: () -> Bool = { false }
  var onStart: () -> Void = {}
  var onFinish: () -> Void = {}
  var onToggle: () -> Void = {}
  var onCancel: () -> Void = {}
  var onUnavailable: () -> Void = {}
  private let decider = ShortcutStateMachine()
  private var tap: ShortcutEventTap?
  private var observers: [NSObjectProtocol] = []

  init() {
    decider.setActionHandler { [weak self] action in
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.perform(action) }
      }
    }
    // Publish both values from the main thread to avoid callbacks from the event tap into the app.
    for name in [
      NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
    ] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in
          MainActor.assumeIsolated { self?.updateShortcutAppFocus() }
        })
    }
    updateShortcutAppFocus()
  }

  var isInstalled: Bool {
    guard AXIsProcessTrusted(), let tap else { return false }
    return tap.isEnabled
  }

  /// Call when the answer of `isBusy` may have changed.
  func updateShortcutAvailability() {
    let busy = isBusy()
    decider.configure { $0.busy = busy }
  }

  func updateShortcutAppFocus() {
    let active = isApplicationActive()
    decider.configure { $0.applicationActive = active }
  }

  @discardableResult func install() -> Bool {
    guard AXIsProcessTrusted() else {
      shutdown()
      return false
    }
    if let tap, !tap.isValid { shutdown() }
    if let tap { return tap.enable() }
    let created = ShortcutEventTap(
      decide: { [decider] type, event in decider.handle(ShortcutEvent(type, event)) },
      disabled: { [decider] in decider.tapDisabled() })
    let enabled = created.start()
    if created.isRunning { tap = created }
    return enabled
  }
  func reset() {
    decider.reset()
  }
  func shutdown() {
    tap?.stop()
    tap = nil
    reset()
  }
  /// Runs the decision for one event on the calling thread.
  func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    updateShortcutAvailability()
    updateShortcutAppFocus()
    return decider.handle(ShortcutEvent(type, event))
  }
  private func perform(_ action: ShortcutAction) {
    switch action {
    case .start: onStart()
    case .finish: onFinish()
    case .toggle: onToggle()
    case .cancel: onCancel()
    case .unavailable: onUnavailable()
    }
  }
}
