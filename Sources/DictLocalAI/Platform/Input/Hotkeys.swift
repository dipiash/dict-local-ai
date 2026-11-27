import AppKit

@MainActor
final class Hotkeys {
  var hold = Shortcut.hold
  var toggle = Shortcut.toggle {
    didSet {
      if toggle != oldValue { cancelPendingToggle() }
    }
  }
  var enabled = true
  var capturing = false
  var isApplicationActive: () -> Bool = { NSApp?.isActive == true }
  var isBusy: () -> Bool = { false }
  var onStart: () -> Void = {}
  var onFinish: () -> Void = {}
  var onToggle: () -> Void = {}
  var onCancel: () -> Void = {}
  var onUnavailable: () -> Void = {}
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var pending: DispatchWorkItem?
  private var pendingToggle: DispatchWorkItem?
  private var toggleKeyDown: UInt16?
  private var holdDown = false
  private var leftOptionDown = false
  private var started = false
  private var ignoreRelease = false
  private var previousTap: TimeInterval = -.infinity
  private var pressedAt: TimeInterval = 0

  var isInstalled: Bool {
    guard AXIsProcessTrusted(), let tap else { return false }
    return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
  }

  @discardableResult func install() -> Bool {
    guard AXIsProcessTrusted() else {
      shutdown()
      return false
    }
    if let tap, !CFMachPortIsValid(tap) { shutdown() }
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: true)
      return CGEvent.tapIsEnabled(tap: tap)
    }
    let mask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)
    guard
      let created = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap,
        options: .defaultTap, eventsOfInterest: CGEventMask(mask),
        callback: { _, type, event, context in
          guard let context else { return Unmanaged.passUnretained(event) }
          let owner = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
          let handled = MainActor.assumeIsolated { owner.handle(type, event) }
          return handled ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return false }
    tap = created
    source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
    if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    CGEvent.tapEnable(tap: created, enable: true)
    return CGEvent.tapIsEnabled(tap: created)
  }
  func reset() {
    pending?.cancel()
    pending = nil
    cancelPendingToggle()
    toggleKeyDown = nil
    holdDown = false
    leftOptionDown = false
    started = false
    ignoreRelease = false
    previousTap = -.infinity
  }
  private func cancelPendingToggle() {
    pendingToggle?.cancel()
    pendingToggle = nil
  }
  func shutdown() {
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let tap { CFMachPortInvalidate(tap) }
    source = nil
    tap = nil
    reset()
  }
  func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      reset()
      DispatchQueue.main.async { [weak self] in
        self?.onUnavailable()
      }
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return false
    }
    guard event.getIntegerValueField(.eventSourceUserData) != TextInsertion.appEventTag else {
      return false
    }
    guard enabled, !capturing else { return false }
    var key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    if key == 53, type == .keyDown, isBusy() || pending != nil || pendingToggle != nil {
      reset()
      DispatchQueue.main.async { [weak self] in
        self?.onCancel()
      }
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
    var toggleFlags = flags
    if let own = Shortcut.modifierKeys[toggle.key] { toggleFlags.remove(own) }
    if key == toggleKeyDown {
      if !down {
        cancelPendingToggle()
        toggleKeyDown = nil
      } else if toggleFlags.rawValue != toggle.modifiers {
        cancelPendingToggle()
      }
      return true
    }
    if type == .keyDown || (type == .flagsChanged && toggleFlags.rawValue != toggle.modifiers) {
      cancelPendingToggle()
    }
    if isApplicationActive(),
      (flags == .maskCommand && [0, 6, 7, 8, 9, 12].contains(key))
        || (flags == [.maskCommand, .maskShift] && key == 6)
    {
      return false
    }
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    if key == toggle.key, toggleFlags.rawValue == toggle.modifiers, down, !isRepeat,
      toggleKeyDown == nil
    {
      toggleKeyDown = key
      if pending != nil {
        pending?.cancel()
        pending = nil
        ignoreRelease = holdDown
      }
      previousTap = -.infinity
      let job = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.pendingToggle = nil
        guard self.enabled, !self.capturing else { return }
        self.ignoreRelease = self.holdDown
        self.onToggle()
      }
      pendingToggle = job
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: job)
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
        if isBusy() {
          ignoreRelease = true
          DispatchQueue.main.async { [weak self] in
            self?.onToggle()
          }
          return true
        }
        if pressedAt - previousTap <= 0.35 {
          ignoreRelease = true
          previousTap = -.infinity
          DispatchQueue.main.async { [weak self] in
            self?.onToggle()
          }
        } else {
          started = false
          let job = DispatchWorkItem { [weak self] in
            guard let self, self.holdDown, !self.ignoreRelease else { return }
            self.started = true
            self.pending = nil
            self.previousTap = -.infinity
            self.onStart()
          }
          pending = job
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: job)
        }
        return true
      }
      if !down, holdDown {
        holdDown = false
        pending?.cancel()
        pending = nil
        if ignoreRelease {
          ignoreRelease = false
          started = false
          return true
        }
        if started {
          started = false
          DispatchQueue.main.async { [weak self] in
            self?.onFinish()
          }
        } else {
          previousTap = ProcessInfo.processInfo.systemUptime
        }
        return true
      }
    }
    return false
  }
}
