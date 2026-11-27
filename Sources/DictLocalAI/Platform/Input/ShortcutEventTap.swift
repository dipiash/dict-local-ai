import AppKit
@preconcurrency import CoreFoundation

/// The system calls the tap needs, so tests can run the thread logic with a fake tap.
struct ShortcutEventTapDriver: Sendable {
  var create: @Sendable (UnsafeMutableRawPointer) -> CFMachPort?
  var setEnabled: @Sendable (CFMachPort, Bool) -> Void
  var isEnabled: @Sendable (CFMachPort) -> Bool

  static let system = ShortcutEventTapDriver(
    create: { owner in
      let mask =
        (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue)
      return CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap,
        options: .defaultTap, eventsOfInterest: CGEventMask(mask),
        callback: { _, type, event, context in
          guard let context else { return Unmanaged.passUnretained(event) }
          let owner = Unmanaged<ShortcutEventTap>.fromOpaque(context).takeUnretainedValue()
          return owner.callback(type, event)
        }, userInfo: owner)
    },
    setEnabled: { CGEvent.tapEnable(tap: $0, enable: $1) },
    isEnabled: { CGEvent.tapIsEnabled(tap: $0) })
}

/// Owns the key event tap and the thread whose run loop serves it, so a busy main thread
/// never delays keyboard input for the whole system.
final class ShortcutEventTap: @unchecked Sendable {
  typealias Decide = @Sendable (CGEventType, CGEvent) -> Bool

  private let decide: Decide
  private let disabled: @Sendable () -> Void
  private let driver: ShortcutEventTapDriver
  private let lock = NSLock()
  private var tap: CFMachPort?
  private var runLoop: CFRunLoop?
  private var lastSlowCallbackReport: TimeInterval = -.infinity

  init(
    decide: @escaping Decide, disabled: @escaping @Sendable () -> Void,
    driver: ShortcutEventTapDriver = .system
  ) {
    self.decide = decide
    self.disabled = disabled
    self.driver = driver
  }

  var isEnabled: Bool {
    guard let tap = currentTap else { return false }
    return CFMachPortIsValid(tap) && driver.isEnabled(tap)
  }

  var isRunning: Bool { currentTap != nil }

  /// The tap handle stays valid until `stop()`, so a stale handle is a tap macOS has torn down.
  var isValid: Bool { currentTap.map { CFMachPortIsValid($0) } ?? false }

  private var currentTap: CFMachPort? {
    lock.lock()
    defer { lock.unlock() }
    return tap
  }

  func enable() -> Bool {
    guard let tap = currentTap else { return false }
    driver.setEnabled(tap, true)
    return driver.isEnabled(tap)
  }

  func start() -> Bool {
    guard !isRunning else { return enable() }
    guard let created = driver.create(Unmanaged.passUnretained(self).toOpaque())
    else { return false }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
    let ready = DispatchSemaphore(value: 0)
    let thread = Thread { [self] in
      let current = CFRunLoopGetCurrent()
      lock.lock()
      runLoop = current
      lock.unlock()
      if let source { CFRunLoopAddSource(current, source, .commonModes) }
      ready.signal()
      CFRunLoopRun()
    }
    thread.name = "app.dictlocalai.hotkeys.tap"
    thread.qualityOfService = .userInteractive
    lock.lock()
    tap = created
    lock.unlock()
    thread.start()
    ready.wait()
    driver.setEnabled(created, true)
    DiagnosticLog.shared.event("hotkeys", "tap_started", "thread=own")
    return driver.isEnabled(created)
  }

  /// Wait for the tap thread to release the event tap before returning.
  func stop() {
    lock.lock()
    let stoppedTap = tap
    let loop = runLoop
    tap = nil
    runLoop = nil
    lock.unlock()
    guard let stoppedTap else { return }
    driver.setEnabled(stoppedTap, false)
    if let loop {
      let done = DispatchSemaphore(value: 0)
      // Run after the current callback on the serial tap thread.
      CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
        CFMachPortInvalidate(stoppedTap)
        CFRunLoopStop(loop)
        done.signal()
      }
      CFRunLoopWakeUp(loop)
      // Limit the wait so shutdown can proceed even if the tap thread stalls.
      _ = done.wait(timeout: .now() + 1)
    } else {
      CFMachPortInvalidate(stoppedTap)
    }
    DiagnosticLog.shared.event("hotkeys", "tap_stopped")
  }

  func callback(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      disabled()
      if let tap = currentTap { driver.setEnabled(tap, true) }
      let reason = type == .tapDisabledByTimeout ? "timeout" : "user_input"
      DiagnosticLog.shared.event("hotkeys", "tap_reenabled", "reason=\(reason)")
      return Unmanaged.passUnretained(event)
    }
    let started = ProcessInfo.processInfo.systemUptime
    let consumed = decide(type, event)
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    if elapsed > 0.05 { logSlow(elapsed, now: started) }
    return consumed ? nil : Unmanaged.passUnretained(event)
  }

  private func logSlow(_ elapsed: TimeInterval, now: TimeInterval) {
    lock.lock()
    let due = now - lastSlowCallbackReport >= 60
    if due { lastSlowCallbackReport = now }
    lock.unlock()
    if due {
      DiagnosticLog.shared.event(
        "hotkeys", "slow_callback", "ms=\(DiagnosticFields.milliseconds(elapsed))")
    }
  }
}
