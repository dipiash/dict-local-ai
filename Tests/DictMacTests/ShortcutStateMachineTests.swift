import AppKit
import XCTest

@testable import DictLocalAI

private final class Actions: @unchecked Sendable {
  private let lock = NSLock()
  private var list: [ShortcutAction] = []
  var all: [ShortcutAction] {
    lock.lock()
    defer { lock.unlock() }
    return list
  }
  func add(_ action: ShortcutAction) {
    lock.lock()
    list.append(action)
    lock.unlock()
  }
}

final class ShortcutStateMachineTests: XCTestCase {
  private let fn = Shortcut(key: 63, modifiers: 0, label: "Fn")
  private let controlSpace = Shortcut(
    key: 49, modifiers: CGEventFlags.maskControl.rawValue, label: "Ctrl Space")

  private func make(_ setup: (inout ShortcutConfiguration) -> Void = { _ in }) -> (
    ShortcutStateMachine, Actions
  ) {
    let actions = Actions()
    let decider = ShortcutStateMachine()
    decider.setActionHandler { actions.add($0) }
    decider.configure { $0.hold = fn }
    decider.configure(setup)
    return (decider, actions)
  }

  private func key(
    _ type: CGEventType, _ code: UInt16, _ flags: CGEventFlags = [], own: Bool = false
  ) -> ShortcutEvent {
    ShortcutEvent(type: type, key: code, flags: flags, isRepeat: false, isOwn: own)
  }

  func testAppGeneratedEventsAreIgnoredByShortcutMatcher() {
    let (decider, actions) = make {
      $0.toggle = Shortcut(key: 9, modifiers: CGEventFlags.maskCommand.rawValue, label: "Cmd V")
    }
    XCTAssertFalse(decider.handle(key(.keyDown, 9, .maskCommand, own: true)))
    XCTAssertFalse(decider.handle(key(.keyUp, 9, .maskCommand, own: true)))
    XCTAssertEqual(actions.all, [])
  }

  @MainActor func testPasteEventsCarryTheOwnMarker() throws {
    let events = try XCTUnwrap(TextInsertion.pasteKeyEvents())
    XCTAssertEqual(events.count, 4)
    for event in events {
      XCTAssertEqual(
        event.getIntegerValueField(.eventSourceUserData), ShortcutEvent.appEventTag)
      XCTAssertTrue(ShortcutEvent(.keyDown, event).isOwn)
    }
  }

  func testNotificationFromAnotherSourceIsNotOwn() throws {
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true))
    XCTAssertFalse(ShortcutEvent(.keyDown, event).isOwn)
  }

  func testEscapeIsConsumedExclusivelyWhileBusy() {
    let (decider, actions) = make()
    XCTAssertFalse(decider.handle(key(.keyDown, 53)))
    decider.configure { $0.busy = true }
    XCTAssertTrue(decider.handle(key(.keyDown, 53)))
    XCTAssertEqual(actions.all, [.cancel])
  }

  func testPausedShortcutsLeaveEventsUnconsumed() {
    let (decider, actions) = make { $0.busy = true }
    decider.configure { $0.enabled = false }
    XCTAssertFalse(decider.handle(key(.keyDown, 53)))
    decider.configure {
      $0.enabled = true
      $0.capturing = true
    }
    XCTAssertFalse(decider.handle(key(.flagsChanged, 63, .maskSecondaryFn)))
    XCTAssertEqual(actions.all, [])
  }

  func testEditingCommandPassesExclusivelyWhenApplicationIsActive() {
    let (decider, _) = make {
      $0.toggle = Shortcut(key: 0, modifiers: CGEventFlags.maskCommand.rawValue, label: "Cmd A")
    }
    decider.configure { $0.applicationActive = true }
    XCTAssertFalse(decider.handle(key(.keyDown, 0, .maskCommand)))
    decider.configure { $0.applicationActive = false }
    XCTAssertTrue(decider.handle(key(.keyDown, 0, .maskCommand)))
  }

  func testHoldBeginsAfterDelayAndFinishesOnRelease() async {
    let (decider, actions) = make()
    XCTAssertTrue(decider.handle(key(.flagsChanged, 63, .maskSecondaryFn)))
    try? await Task.sleep(nanoseconds: 400_000_000)
    XCTAssertEqual(actions.all, [.start])
    XCTAssertTrue(decider.handle(key(.flagsChanged, 63)))
    XCTAssertEqual(actions.all, [.start, .finish])
  }

  func testResetDisarmsHoldTimer() async {
    let (decider, actions) = make()
    _ = decider.handle(key(.flagsChanged, 63, .maskSecondaryFn))
    decider.reset()
    try? await Task.sleep(nanoseconds: 400_000_000)
    XCTAssertEqual(actions.all, [])
  }

  func testShortcutChangeInvalidatesPendingToggle() async {
    let (decider, actions) = make { $0.toggle = controlSpace }
    XCTAssertTrue(decider.handle(key(.keyDown, 49, .maskControl)))
    decider.configure { $0.toggle = Shortcut(key: 50, modifiers: 0, label: "other") }
    try? await Task.sleep(nanoseconds: 600_000_000)
    XCTAssertEqual(actions.all, [])
  }

  func testSameToggleShortcutPreservesPendingToggle() async {
    let (decider, actions) = make { $0.toggle = controlSpace }
    XCTAssertTrue(decider.handle(key(.keyDown, 49, .maskControl)))
    decider.configure { $0.toggle = controlSpace }
    try? await Task.sleep(nanoseconds: 600_000_000)
    XCTAssertEqual(actions.all, [.toggle])
  }

  func testTapDisabledResetsAndRecordsUnavailable() {
    let (decider, actions) = make()
    _ = decider.handle(key(.flagsChanged, 63, .maskSecondaryFn))
    decider.tapDisabled()
    XCTAssertEqual(actions.all, [.unavailable])
    // The next press after reset begins a new hold.
    XCTAssertTrue(decider.handle(key(.flagsChanged, 63, .maskSecondaryFn)))
  }

  func testShortcutEvaluationCanRunOnAWorker() async {
    let (decider, actions) = make { $0.busy = true }
    let event = key(.keyDown, 53)
    let consumed = await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: decider.handle(event))
      }
    }
    XCTAssertTrue(consumed)
    XCTAssertEqual(actions.all, [.cancel])
  }

  func testDiagnosticDurationUsesMilliseconds() {
    XCTAssertEqual(DiagnosticFields.milliseconds(0.0734), "73")
  }
}
