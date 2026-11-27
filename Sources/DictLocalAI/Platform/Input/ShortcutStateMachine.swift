import AppKit

enum ShortcutAction: Equatable, Sendable {
  case start, finish, toggle, cancel, unavailable
}

/// The fields of a key event that the decision needs, so it can run without the event object.
struct ShortcutEvent: Sendable {
  /// Tag app-generated events so the shortcut handler ignores them.
  static let appEventTag: Int64 = 0x444C_4149

  var type: CGEventType
  var key: UInt16
  var flags: CGEventFlags
  var isRepeat: Bool
  var isOwn: Bool

  init(type: CGEventType, key: UInt16, flags: CGEventFlags, isRepeat: Bool, isOwn: Bool = false) {
    self.type = type
    self.key = key
    self.flags = flags
    self.isRepeat = isRepeat
    self.isOwn = isOwn
  }

  init(_ type: CGEventType, _ event: CGEvent) {
    self.init(
      type: type,
      key: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
      flags: event.flags,
      isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
      isOwn: event.getIntegerValueField(.eventSourceUserData) == Self.appEventTag)
  }
}

/// Settings the tap thread reads. Main sets them, the tap thread only sees this copy under the lock.
struct ShortcutConfiguration: Sendable {
  var hold = Shortcut.hold
  var toggle = Shortcut.toggle
  var enabled = true
  var capturing = false
  var busy = false
  var applicationActive = false
}

/// The hold and toggle state machine. All state is behind one lock, so the tap thread,
/// the timer queue and the main thread can call it. Actions go out through `emit`,
/// always under the lock, so they leave in the order they were decided.
final class ShortcutStateMachine: @unchecked Sendable {
  private let holdDelay: TimeInterval
  private let toggleDelay: TimeInterval
  private let lock = NSLock()
  private let timers = DispatchQueue(label: "app.dictlocalai.hotkeys.timers")
  private var emitter: @Sendable (ShortcutAction) -> Void = { _ in }
  private var config = ShortcutConfiguration()
  private var holdTimerToken: Int?
  private var toggleTimerToken: Int?
  private var nextID = 0
  private var toggleKeyDown: UInt16?
  private var holdDown = false
  private var leftOptionDown = false
  private var started = false
  private var ignoreRelease = false
  private var previousTap: TimeInterval = -.infinity
  private var pressedAt: TimeInterval = 0

  init(holdDelay: TimeInterval = 0.18, toggleDelay: TimeInterval = 0.35) {
    self.holdDelay = holdDelay
    self.toggleDelay = toggleDelay
  }

  func setActionHandler(_ emitter: @escaping @Sendable (ShortcutAction) -> Void) {
    lock.lock()
    self.emitter = emitter
    lock.unlock()
  }

  /// Queue the action without running app code while holding the lock.
  private func sendActionWhileLocked(_ action: ShortcutAction) {
    emitter(action)
  }

  func configure(_ change: (inout ShortcutConfiguration) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    let old = config
    change(&config)
    if config.toggle != old.toggle { toggleTimerToken = nil }
  }

  func reset() {
    lock.lock()
    clearStateWhileLocked()
    lock.unlock()
  }

  /// Returns true when the event is ours and must not reach other apps.
  func handle(_ event: ShortcutEvent) -> Bool {
    lock.lock()
    var actions: [ShortcutAction] = []
    let consumed = decide(event, &actions)
    for action in actions { sendActionWhileLocked(action) }
    lock.unlock()
    return consumed
  }

  func tapDisabled() {
    lock.lock()
    clearStateWhileLocked()
    sendActionWhileLocked(.unavailable)
    lock.unlock()
  }

  private func clearStateWhileLocked() {
    holdTimerToken = nil
    toggleTimerToken = nil
    toggleKeyDown = nil
    holdDown = false
    leftOptionDown = false
    started = false
    ignoreRelease = false
    previousTap = -.infinity
  }

  private func nextTimerToken() -> Int {
    nextID += 1
    return nextID
  }

  private func decide(_ event: ShortcutEvent, _ actions: inout [ShortcutAction]) -> Bool {
    if event.isOwn { return false }
    let type = event.type
    guard config.enabled, !config.capturing else { return false }
    var key = event.key
    if key == 53, type == .keyDown,
      config.busy || started || holdTimerToken != nil || toggleTimerToken != nil
    {
      clearStateWhileLocked()
      actions.append(.cancel)
      return true
    }
    let flags = event.flags.intersection(Shortcut.mask)
    var down: Bool
    if type == .flagsChanged, let flag = Shortcut.modifierKeys[key] {
      down = flags.contains(flag)
    } else {
      down = type == .keyDown
    }
    if type == .flagsChanged, key == 58 { leftOptionDown = down }
    let toggle = config.toggle
    let hold = config.hold
    var toggleFlags = flags
    if let own = Shortcut.modifierKeys[toggle.key] { toggleFlags.remove(own) }
    if key == toggleKeyDown {
      if !down {
        toggleTimerToken = nil
        toggleKeyDown = nil
      } else if toggleFlags.rawValue != toggle.modifiers {
        toggleTimerToken = nil
      }
      return true
    }
    if type == .keyDown || (type == .flagsChanged && toggleFlags.rawValue != toggle.modifiers) {
      toggleTimerToken = nil
    }
    if config.applicationActive,
      (flags == .maskCommand && [0, 6, 7, 8, 9, 12].contains(key))
        || (flags == [.maskCommand, .maskShift] && key == 6)
    {
      return false
    }
    let isRepeat = event.isRepeat
    if key == toggle.key, toggleFlags.rawValue == toggle.modifiers, down, !isRepeat,
      toggleKeyDown == nil
    {
      toggleKeyDown = key
      if holdTimerToken != nil {
        holdTimerToken = nil
        ignoreRelease = holdDown
      }
      previousTap = -.infinity
      let id = nextTimerToken()
      toggleTimerToken = id
      timers.asyncAfter(deadline: .now() + toggleDelay) { [weak self] in
        self?.activatePendingToggle(id)
      }
      return true
    }
    if type == .flagsChanged {
      // This device flag identifies left Option.
      let leftOption = leftOptionDown || event.flags.rawValue & 0x20 != 0
      if hold == .hold {
        if flags.contains([.maskAlternate, .maskSecondaryFn]), leftOption {
          key = hold.key
          down = true
        } else if holdDown {
          key = hold.key
          down = false
        }
      }
    }
    if isRepeat { return holdDown && key == hold.key }
    if key == hold.key {
      var modifiers = flags
      if let own = Shortcut.modifierKeys[key] { modifiers.remove(own) }
      if down, modifiers.rawValue == hold.modifiers {
        guard !holdDown else { return true }
        holdDown = true
        pressedAt = ProcessInfo.processInfo.systemUptime
        if config.busy {
          ignoreRelease = true
          actions.append(.toggle)
          return true
        }
        if pressedAt - previousTap <= 0.35 {
          ignoreRelease = true
          previousTap = -.infinity
          actions.append(.toggle)
        } else {
          started = false
          let id = nextTimerToken()
          holdTimerToken = id
          timers.asyncAfter(deadline: .now() + holdDelay) { [weak self] in
            self?.activatePendingHold(id)
          }
        }
        return true
      }
      if !down, holdDown {
        holdDown = false
        holdTimerToken = nil
        if ignoreRelease {
          ignoreRelease = false
          started = false
          return true
        }
        if started {
          started = false
          actions.append(.finish)
        } else {
          previousTap = ProcessInfo.processInfo.systemUptime
        }
        return true
      }
    }
    return false
  }

  // Timer tokens invalidate callbacks left over after reset or a newer press.
  private func activatePendingToggle(_ id: Int) {
    lock.lock()
    guard toggleTimerToken == id else {
      lock.unlock()
      return
    }
    toggleTimerToken = nil
    guard config.enabled, !config.capturing else {
      lock.unlock()
      return
    }
    ignoreRelease = holdDown
    sendActionWhileLocked(.toggle)
    lock.unlock()
  }

  private func activatePendingHold(_ id: Int) {
    lock.lock()
    guard holdTimerToken == id, holdDown, !ignoreRelease else {
      lock.unlock()
      return
    }
    started = true
    holdTimerToken = nil
    previousTap = -.infinity
    sendActionWhileLocked(.start)
    lock.unlock()
  }
}
