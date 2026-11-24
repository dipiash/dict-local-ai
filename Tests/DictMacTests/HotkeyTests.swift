import AppKit
import XCTest

@testable import DictLocalAI

@MainActor
final class HotkeyTests: XCTestCase {
  private func event(_ key: UInt16, _ flags: CGEventFlags = [], repeatKey: Bool = false) -> CGEvent
  {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
    event.flags = flags
    event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
    return event
  }
  @MainActor
  func testOrdinarySpaceRepeatsPassThrough() async {
    let keys = Hotkeys()
    keys.hold = Shortcut(key: 63, modifiers: 0, label: "Fn")
    XCTAssertFalse(keys.handle(.keyDown, event(49, repeatKey: true)))
    XCTAssertFalse(keys.handle(.keyDown, event(0, repeatKey: true)))
  }
  @MainActor
  func testDoubleFnStartsHandsFreeOnlyOnce() async {
    let keys = Hotkeys()
    keys.hold = Shortcut(key: 63, modifiers: 0, label: "Fn")
    let toggled = expectation(description: "double Fn toggles dictation")
    var toggles = 0
    keys.onToggle = {
      toggles += 1
      toggled.fulfill()
    }
    _ = keys.handle(.flagsChanged, event(63, .maskSecondaryFn))
    _ = keys.handle(.flagsChanged, event(63))
    _ = keys.handle(.flagsChanged, event(63, .maskSecondaryFn))
    _ = keys.handle(.flagsChanged, event(63))
    let toggleResult = await XCTWaiter.fulfillment(of: [toggled], timeout: 1)
    XCTAssertEqual(toggleResult, .completed)
    XCTAssertEqual(toggles, 1)
    keys.reset()
  }
  @MainActor
  func testCancelDoesNotPoisonNextHold() async {
    let keys = Hotkeys()
    keys.hold = Shortcut(key: 63, modifiers: 0, label: "Fn")
    let first = expectation(description: "first hold")
    keys.onStart = { first.fulfill() }
    _ = keys.handle(.flagsChanged, event(63, .maskSecondaryFn))
    let firstResult = await XCTWaiter.fulfillment(of: [first], timeout: 1)
    XCTAssertEqual(firstResult, .completed)
    let cancelled = expectation(description: "Escape cancels dictation")
    keys.onCancel = {
      keys.reset()
      cancelled.fulfill()
    }
    keys.isBusy = { true }
    XCTAssertTrue(keys.handle(.keyDown, event(53, .maskSecondaryFn)))
    let cancelResult = await XCTWaiter.fulfillment(of: [cancelled], timeout: 1)
    XCTAssertEqual(cancelResult, .completed)
    keys.isBusy = { false }
    _ = keys.handle(.flagsChanged, event(63))
    let next = expectation(description: "next hold")
    keys.onStart = { next.fulfill() }
    _ = keys.handle(.flagsChanged, event(63, .maskSecondaryFn))
    let nextResult = await XCTWaiter.fulfillment(of: [next], timeout: 1)
    XCTAssertEqual(nextResult, .completed)
    keys.reset()
  }
  @MainActor
  func testSeparateToggleDoesNotPoisonHold() async {
    let keys = Hotkeys()
    keys.hold = Shortcut(key: 63, modifiers: 0, label: "Fn")
    keys.toggle = Shortcut(
      key: 49, modifiers: CGEventFlags.maskControl.rawValue, label: "Ctrl Space")
    let toggled = expectation(description: "separate shortcut toggles dictation")
    keys.onToggle = { toggled.fulfill() }
    XCTAssertTrue(keys.handle(.keyDown, event(49, .maskControl)))
    let toggleResult = await XCTWaiter.fulfillment(of: [toggled], timeout: 1)
    XCTAssertEqual(toggleResult, .completed)
    _ = keys.handle(.keyUp, event(49, .maskControl))
    let next = expectation(description: "hold after toggle")
    keys.onStart = { next.fulfill() }
    _ = keys.handle(.flagsChanged, event(63, .maskSecondaryFn))
    let nextResult = await XCTWaiter.fulfillment(of: [next], timeout: 1)
    XCTAssertEqual(nextResult, .completed)
    keys.reset()
  }
  func testQuickToggleChordsDoNotStartDictation() async {
    let keys = Hotkeys()
    let toggled = expectation(description: "releasing either key cancels the toggle")
    toggled.isInverted = true
    keys.onToggle = { toggled.fulfill() }

    XCTAssertFalse(keys.handle(.flagsChanged, event(63, .maskSecondaryFn)))
    XCTAssertTrue(keys.handle(.keyDown, event(49, .maskSecondaryFn)))
    XCTAssertTrue(keys.handle(.keyUp, event(49, .maskSecondaryFn)))
    XCTAssertFalse(keys.handle(.flagsChanged, event(63)))

    keys.toggle = Shortcut(
      key: 49, modifiers: CGEventFlags.maskControl.rawValue, label: "Ctrl Space")
    XCTAssertTrue(keys.handle(.keyDown, event(49, .maskControl)))
    XCTAssertFalse(keys.handle(.flagsChanged, event(59)))
    XCTAssertFalse(keys.handle(.flagsChanged, event(59, .maskControl)))

    let result = await XCTWaiter.fulfillment(of: [toggled], timeout: 0.5)
    XCTAssertEqual(result, .completed)
    XCTAssertTrue(keys.handle(.keyUp, event(49, .maskControl)))
  }

  func testHeldToggleFiresOnceUntilRelease() async {
    let keys = Hotkeys()
    let toggled = expectation(description: "holding Fn and Space toggles dictation")
    var toggles = 0
    keys.onToggle = {
      toggles += 1
      toggled.fulfill()
    }
    XCTAssertTrue(keys.handle(.keyDown, event(49, .maskSecondaryFn)))
    XCTAssertEqual(toggles, 0)
    XCTAssertTrue(keys.handle(.keyDown, event(49, .maskSecondaryFn, repeatKey: true)))
    let result = await XCTWaiter.fulfillment(of: [toggled], timeout: 1)
    XCTAssertEqual(result, .completed)

    XCTAssertTrue(keys.handle(.keyDown, event(49, .maskSecondaryFn)))
    XCTAssertTrue(keys.handle(.keyDown, event(49, .maskSecondaryFn, repeatKey: true)))
    let repeated = expectation(description: "held shortcut does not toggle again")
    repeated.isInverted = true
    keys.onToggle = { repeated.fulfill() }
    let repeatResult = await XCTWaiter.fulfillment(of: [repeated], timeout: 0.5)
    XCTAssertEqual(repeatResult, .completed)
    XCTAssertTrue(keys.handle(.keyUp, event(49)))
    XCTAssertEqual(toggles, 1)
  }

  @MainActor
  func testShutdownCancelsPendingHoldAndAllowsNextHold() async {
    let keys = Hotkeys()
    keys.hold = Shortcut(key: 63, modifiers: 0, label: "Fn")
    let cancelled = expectation(description: "pending hold is cancelled")
    cancelled.isInverted = true
    keys.onStart = { cancelled.fulfill() }
    _ = keys.handle(.flagsChanged, event(63, .maskSecondaryFn))
    keys.shutdown()
    let cancelledResult = await XCTWaiter.fulfillment(of: [cancelled], timeout: 0.25)
    XCTAssertEqual(cancelledResult, .completed)
    let next = expectation(description: "hold after shutdown")
    keys.onStart = { next.fulfill() }
    _ = keys.handle(.flagsChanged, event(63, .maskSecondaryFn))
    let nextResult = await XCTWaiter.fulfillment(of: [next], timeout: 1)
    XCTAssertEqual(nextResult, .completed)
    keys.reset()
  }
  func testDefaultLeftOptionThenFnStartsAndFinishesOnFnRelease() async {
    let keys = Hotkeys()
    let started = expectation(description: "left Option then Fn")
    keys.onStart = { started.fulfill() }
    let finished = expectation(description: "release finishes dictation")
    keys.onFinish = { finished.fulfill() }
    XCTAssertFalse(keys.handle(.flagsChanged, event(58, .maskAlternate)))
    XCTAssertTrue(keys.handle(.flagsChanged, event(63, [.maskAlternate, .maskSecondaryFn])))
    let result = await XCTWaiter.fulfillment(of: [started], timeout: 1)
    XCTAssertEqual(result, .completed)
    XCTAssertTrue(keys.handle(.flagsChanged, event(63, .maskAlternate)))
    let finishResult = await XCTWaiter.fulfillment(of: [finished], timeout: 1)
    XCTAssertEqual(finishResult, .completed)
    keys.reset()
  }

  func testDefaultFnThenLeftOptionStartsAndFinishesOnOptionRelease() async {
    let keys = Hotkeys()
    let started = expectation(description: "Fn then left Option")
    keys.onStart = { started.fulfill() }
    let finished = expectation(description: "release finishes dictation")
    keys.onFinish = { finished.fulfill() }
    XCTAssertFalse(keys.handle(.flagsChanged, event(63, .maskSecondaryFn)))
    XCTAssertTrue(keys.handle(.flagsChanged, event(58, [.maskAlternate, .maskSecondaryFn])))
    let result = await XCTWaiter.fulfillment(of: [started], timeout: 1)
    XCTAssertEqual(result, .completed)
    XCTAssertTrue(keys.handle(.flagsChanged, event(58, .maskSecondaryFn)))
    let finishResult = await XCTWaiter.fulfillment(of: [finished], timeout: 1)
    XCTAssertEqual(finishResult, .completed)
    keys.reset()
  }

  func testDefaultIgnoresFnAloneAndRightOption() async {
    let keys = Hotkeys()
    let started = expectation(description: "wrong chord does not start")
    started.isInverted = true
    keys.onStart = { started.fulfill() }
    XCTAssertFalse(keys.handle(.flagsChanged, event(63, .maskSecondaryFn)))
    XCTAssertFalse(keys.handle(.flagsChanged, event(61, [.maskAlternate, .maskSecondaryFn])))
    let result = await XCTWaiter.fulfillment(of: [started], timeout: 0.25)
    XCTAssertEqual(result, .completed)
    keys.reset()
  }

  @MainActor
  func testPhysicalShortcutEqualityIgnoresLabel() async {
    XCTAssertEqual(
      Shortcut.hold,
      Shortcut(key: 58, modifiers: CGEventFlags.maskSecondaryFn.rawValue, label: "Left Option + Fn")
    )
  }
  @MainActor
  func testEscapeConsumesOnlyDuringDictation() async {
    let keys = Hotkeys()
    keys.hold = Shortcut(key: 63, modifiers: 0, label: "Fn")
    let cancelled = expectation(description: "Escape cancels active dictation")
    keys.onCancel = { cancelled.fulfill() }
    keys.isBusy = { true }
    XCTAssertTrue(keys.handle(.keyDown, event(53, .maskSecondaryFn)))
    let cancelResult = await XCTWaiter.fulfillment(of: [cancelled], timeout: 1)
    XCTAssertEqual(cancelResult, .completed)
    keys.isBusy = { false }
    XCTAssertFalse(keys.handle(.keyDown, event(53)))
  }
}
