import AppKit
import XCTest

@testable import DictLocalAI

@MainActor
final class TextInsertionTests: XCTestCase {
  func testSyntheticPasteIncludesPhysicalCommandModifierEvents() throws {
    let events = try XCTUnwrap(TextInsertion.pasteKeyEvents())
    XCTAssertEqual(events.count, 4)
    XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
    XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [55, 9, 9, 55])
    XCTAssertEqual(events[0].flags, .maskCommand)
    XCTAssertEqual(events[1].flags, .maskCommand)
    XCTAssertEqual(events[2].flags, .maskCommand)
    XCTAssertFalse(events[3].flags.contains(.maskCommand))
  }

  func testMissingCapturedTargetNeverChangesClipboard() {
    let previousChange = NSPasteboard.general.changeCount
    XCTAssertEqual(TextInsertion.insert("test recognized text", target: nil), .unavailable)
    XCTAssertEqual(NSPasteboard.general.changeCount, previousChange)
  }
}
