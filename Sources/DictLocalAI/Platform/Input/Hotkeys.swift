import AppKit

@MainActor
final class Hotkeys {
  var hold = Shortcut.hold
  var toggle = Shortcut.toggle
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
    holdDown = false
    leftOptionDown = false
    started = false
    ignoreRelease = false
    previousTap = -.infinity
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
    guard enabled, !capturing else { return false }
    var key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    if key == 53, type == .keyDown, isBusy() || pending != nil {
      reset()
      DispatchQueue.main.async { [weak self] in
        self?.onCancel()
      }
      return true
    }
    let flags = event.flags.intersection(Shortcut.mask)
    if isApplicationActive(),
      (flags == .maskCommand && [0, 6, 7, 8, 9, 12].contains(key))
        || (flags == [.maskCommand, .maskShift] && key == 6)
    {
      return false
    }
    var down: Bool
    if type == .flagsChanged, let flag = Shortcut.modifierKeys[key] {
      down = flags.contains(flag)
    } else {
      down = type == .keyDown
    }
    if type == .flagsChanged {
      if key == 58 { leftOptionDown = down }
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
    var toggleFlags = flags
    if let own = Shortcut.modifierKeys[toggle.key] { toggleFlags.remove(own) }
    let toggleMatches = key == toggle.key && toggleFlags.rawValue == toggle.modifiers
    if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
      return (holdDown && key == hold.key)
        || toggleMatches
    }
    if toggleMatches, down {
      pending?.cancel()
      pending = nil
      ignoreRelease = holdDown
      previousTap = -.infinity
      DispatchQueue.main.async { [weak self] in
        self?.onToggle()
      }
      return true
    }
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
