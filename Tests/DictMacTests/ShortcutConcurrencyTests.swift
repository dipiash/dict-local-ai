import AppKit
import XCTest

@testable import DictLocalAI

private final class Recorder: @unchecked Sendable {
  private let lock = NSLock()
  private var list: [ShortcutAction] = []
  private let startEntered = DispatchSemaphore(value: 0)
  private let startMayFinish = DispatchSemaphore(value: 0)
  private var blocksStart = false

  var all: [ShortcutAction] {
    lock.lock()
    defer { lock.unlock() }
    return list
  }

  /// Makes `.start` wait inside the emitter, like a timer thread that lost the CPU before queueing.
  func blockStart() { blocksStart = true }
  func waitForStartEntered() -> Bool { startEntered.wait(timeout: .now() + 5) == .success }
  func letStartFinish() { startMayFinish.signal() }

  func emit(_ action: ShortcutAction) {
    if action == .start, blocksStart {
      startEntered.signal()
      _ = startMayFinish.wait(timeout: .now() + 5)
    }
    lock.lock()
    list.append(action)
    lock.unlock()
  }
}

private final class FakeTapDriver: @unchecked Sendable {
  private let lock = NSLock()
  private var enabled = Set<ObjectIdentifier>()
  private(set) var ports: [CFMachPort] = []

  var driver: ShortcutEventTapDriver {
    ShortcutEventTapDriver(
      create: { [self] _ in
        let port = CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, nil, nil)
        lock.lock()
        if let port { ports.append(port) }
        lock.unlock()
        return port
      },
      setEnabled: { [self] port, on in
        lock.lock()
        if on {
          enabled.insert(ObjectIdentifier(port))
        } else {
          enabled.remove(ObjectIdentifier(port))
        }
        lock.unlock()
      },
      isEnabled: { [self] port in
        lock.lock()
        defer { lock.unlock() }
        return enabled.contains(ObjectIdentifier(port))
      })
  }
}

final class ShortcutConcurrencyTests: XCTestCase {
  private let fn = Shortcut(key: 63, modifiers: 0, label: "Fn")

  private func make(
    holdDelay: TimeInterval = 0.18, _ setup: (inout ShortcutConfiguration) -> Void = { _ in }
  ) -> (ShortcutStateMachine, Recorder) {
    let recorder = Recorder()
    let decider = ShortcutStateMachine(holdDelay: holdDelay)
    decider.setActionHandler { recorder.emit($0) }
    decider.configure { $0.hold = fn }
    decider.configure(setup)
    return (decider, recorder)
  }

  private func press() -> ShortcutEvent {
    ShortcutEvent(type: .flagsChanged, key: 63, flags: .maskSecondaryFn, isRepeat: false)
  }
  private func release() -> ShortcutEvent {
    ShortcutEvent(type: .flagsChanged, key: 63, flags: [], isRepeat: false)
  }
  private func escape() -> ShortcutEvent {
    ShortcutEvent(type: .keyDown, key: 53, flags: [], isRepeat: false)
  }

  /// Start and finish actions must alternate in sequence.
  private func assertWellFormed(
    _ actions: [ShortcutAction], file: StaticString = #filePath, line: UInt = #line
  ) {
    var started = false
    for (index, action) in actions.enumerated() {
      switch action {
      case .start:
        XCTAssertFalse(started, "duplicate start at \(index): \(actions)", file: file, line: line)
        started = true
      case .finish:
        XCTAssertTrue(
          started, "finish without start at \(index): \(actions)", file: file, line: line)
        started = false
      case .cancel: started = false
      case .toggle, .unavailable: break
      }
    }
    XCTAssertFalse(started, "recording never finished: \(actions)", file: file, line: line)
  }

  private func spin(_ microseconds: UInt32) {
    usleep(microseconds)
  }

  // MARK: Event order and cancellation

  func testFinishFollowsStartEvenWhenTimerThreadPauses() {
    let (decider, recorder) = make(holdDelay: 0.02)
    recorder.blockStart()
    XCTAssertTrue(decider.handle(press()))
    XCTAssertTrue(recorder.waitForStartEntered())
    let released = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      _ = decider.handle(self.release())
      released.signal()
    }
    // Let release run before the start action reaches the queue.
    usleep(100_000)
    recorder.letStartFinish()
    XCTAssertEqual(released.wait(timeout: .now() + 5), .success)
    XCTAssertEqual(recorder.all, [.start, .finish])
  }

  func testEscapeIsHandledImmediatelyAfterActivation() {
    let (decider, recorder) = make(holdDelay: 0.02)
    recorder.blockStart()
    XCTAssertTrue(decider.handle(press()))
    XCTAssertTrue(recorder.waitForStartEntered())
    let consumed = DispatchSemaphore(value: 0)
    let result = Box<Bool>(false)
    DispatchQueue.global().async {
      result.value = decider.handle(self.escape())
      consumed.signal()
    }
    usleep(50_000)
    recorder.letStartFinish()
    XCTAssertEqual(consumed.wait(timeout: .now() + 5), .success)
    XCTAssertTrue(result.value, "Escape reached the focused app before recording began")
    XCTAssertEqual(recorder.all, [.start, .cancel])
  }

  // MARK: Concurrent keyboard input

  func testConcurrentActionsCompleteInStartFinishOrder() {
    let (decider, recorder) = make(holdDelay: 0.003)
    let group = DispatchGroup()
    let keyboardDone = Box<Bool>(false)
    let other = Shortcut(key: 49, modifiers: CGEventFlags.maskControl.rawValue, label: "Ctrl Space")
    let shortcuts = [Shortcut.toggle, other]
    for worker in 0..<3 {
      DispatchQueue.global().async(group: group) {
        var n = worker
        while !keyboardDone.value {
          n += 1
          decider.configure {
            $0.busy = n % 7 == 0
            $0.applicationActive = n % 2 == 0
            $0.toggle = shortcuts[n % 2]
          }
        }
      }
    }
    DispatchQueue.global().async(group: group) {
      while !keyboardDone.value {
        _ = decider.handle(
          ShortcutEvent(type: .keyDown, key: 0, flags: .maskCommand, isRepeat: false))
        _ = decider.handle(
          ShortcutEvent(type: .keyUp, key: 0, flags: .maskCommand, isRepeat: false))
      }
    }
    let keyboard = DispatchGroup()
    DispatchQueue.global(qos: .userInteractive).async(group: keyboard) {
      for cycle in 0..<300 {
        _ = decider.handle(self.press())
        self.spin(UInt32(cycle % 7) * 1_000)
        _ = decider.handle(self.release())
        self.spin(500)
      }
      keyboardDone.value = true
    }
    XCTAssertEqual(keyboard.wait(timeout: .now() + 30), .success, "the keyboard thread timed out")
    XCTAssertEqual(group.wait(timeout: .now() + 30), .success, "the test worker timed out")
    usleep(50_000)
    let actions = recorder.all
    assertWellFormed(actions)
    let starts = actions.filter { $0 == .start }.count
    let finishes = actions.filter { $0 == .finish }.count
    XCTAssertEqual(starts, finishes)
    XCTAssertGreaterThan(starts, 0, "no press activated hold-to-talk during the stress test")
  }

  // MARK: Timer cancellation races

  func testConcurrentReleaseEitherCancelsOrFinishesHold() {
    for iteration in 0..<400 {
      let (decider, recorder) = make(holdDelay: 0.001)
      _ = decider.handle(press())
      spin(UInt32(iteration % 5) * 400)
      _ = decider.handle(release())
      usleep(4_000)
      let actions = recorder.all
      XCTAssertTrue(
        actions == [] || actions == [.start, .finish], "iteration \(iteration): \(actions)")
    }
  }

  func testResetPreventsLateStartActions() {
    for iteration in 0..<400 {
      let (decider, recorder) = make(holdDelay: 0.001)
      _ = decider.handle(press())
      spin(UInt32(iteration % 5) * 400)
      decider.reset()
      let countAtReset = recorder.all.count
      usleep(4_000)
      XCTAssertEqual(
        recorder.all.count, countAtReset, "recording started after reset in iteration \(iteration)")
      _ = decider.handle(release())
      XCTAssertFalse(
        recorder.all.contains(.finish), "recording finished after reset in iteration \(iteration)")
    }
  }

  func testResetAndNewPressInvalidateOldHoldTimer() {
    for iteration in 0..<400 {
      let (decider, recorder) = make(holdDelay: 0.001)
      _ = decider.handle(press())
      spin(UInt32(iteration % 5) * 400)
      let resetDone = DispatchSemaphore(value: 0)
      DispatchQueue.global().async {
        decider.reset()
        resetDone.signal()
      }
      resetDone.wait()
      // Measure actions emitted after reset because the first press may already have started.
      let countAtReset = recorder.all.count
      _ = decider.handle(press())
      _ = decider.handle(release())
      usleep(4_000)
      assertWellFormed(Array(recorder.all.dropFirst(countAtReset)))
    }
  }

  // MARK: Event tap lifecycle

  func testInstallAndStopLoopWithFakeTapPreservesGoingAndThreadsEnd() {
    let fake = FakeTapDriver()
    var weakTaps: [WeakTap] = []
    var slowest: TimeInterval = 0
    for iteration in 0..<300 {
      let tap = ShortcutEventTap(decide: { _, _ in false }, disabled: {}, driver: fake.driver)
      weakTaps.append(WeakTap(tap))
      XCTAssertTrue(tap.start(), "iteration \(iteration)")
      XCTAssertTrue(tap.isRunning)
      let busy = Box<Bool>(iteration % 2 == 0)
      let finished = DispatchSemaphore(value: 0)
      if busy.value {
        // Deliver keyboard events concurrently with tap shutdown.
        DispatchQueue.global().async {
          if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
            while busy.value { _ = tap.callback(.keyDown, event) }
          }
          finished.signal()
        }
      } else {
        finished.signal()
      }
      let began = ProcessInfo.processInfo.systemUptime
      tap.stop()
      slowest = max(slowest, ProcessInfo.processInfo.systemUptime - began)
      busy.value = false
      XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
      XCTAssertFalse(tap.isRunning)
    }
    XCTAssertLessThan(slowest, 1.0, "stopping the tap took at least one second")
    for port in fake.ports { XCTAssertFalse(CFMachPortIsValid(port)) }
    // Tap deallocation confirms its owning thread has exited.
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while weakTaps.contains(where: { $0.value != nil }),
      ProcessInfo.processInfo.systemUptime < deadline
    {
      usleep(20_000)
    }
    XCTAssertEqual(
      weakTaps.filter { $0.value != nil }.count, 0, "the event tap threads remained alive")
  }

  func testStoppedTapHandlesLateEventsSafely() throws {
    let fake = FakeTapDriver()
    let calls = Box<Int>(0)
    let tap = ShortcutEventTap(
      decide: { _, _ in
        calls.value += 1
        return false
      }, disabled: {}, driver: fake.driver)
    XCTAssertTrue(tap.start())
    tap.stop()
    tap.stop()
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
    XCTAssertNotNil(tap.callback(.keyDown, event))
    XCTAssertNotNil(tap.callback(.tapDisabledByTimeout, event))
    XCTAssertFalse(tap.isRunning)
    XCTAssertFalse(tap.isEnabled)
    XCTAssertTrue(tap.start(), "the event tap should restart after stopping")
    tap.stop()
  }
}

private final class Box<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: T
  init(_ value: T) { stored = value }
  var value: T {
    get {
      lock.lock()
      defer { lock.unlock() }
      return stored
    }
    set {
      lock.lock()
      stored = newValue
      lock.unlock()
    }
  }
}

private final class WeakTap {
  weak var value: ShortcutEventTap?
  init(_ value: ShortcutEventTap) { self.value = value }
}
