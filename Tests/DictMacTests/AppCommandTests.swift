import AppKit
import XCTest

@testable import DictLocalAI

@MainActor
final class AppCommandTests: XCTestCase {
  func testStandardEditMenuUsesResponderChainAndQuitUsesTerminate() throws {
    _ = NSApplication.shared
    let menu = ApplicationMenus.make()
    let application = try XCTUnwrap(menu.items.first?.submenu)
    let quit = try XCTUnwrap(application.items.first { $0.keyEquivalent == "q" })
    XCTAssertEqual(quit.action, #selector(NSApplication.terminate(_:)))
    XCTAssertEqual(quit.keyEquivalentModifierMask, .command)
    let edit = try XCTUnwrap(menu.items.first { $0.title == L10n.text("menu.edit") }?.submenu)
    let commands = ["a": "selectAll:", "c": "copy:", "v": "paste:", "x": "cut:"]
    for (key, selector) in commands {
      let item = try XCTUnwrap(edit.items.first { $0.keyEquivalent == key })
      XCTAssertEqual(item.action, Selector(selector))
      XCTAssertNil(item.target)
      XCTAssertEqual(item.keyEquivalentModifierMask, .command)
    }
    let undo = try XCTUnwrap(edit.items.first { $0.action == Selector(("undo:")) })
    let redo = try XCTUnwrap(edit.items.first { $0.action == Selector(("redo:")) })
    XCTAssertEqual(undo.keyEquivalentModifierMask, .command)
    XCTAssertEqual(redo.keyEquivalentModifierMask, [.command, .shift])
  }

  func testSettingsShortcutUsesNativeCommandComma() throws {
    _ = NSApplication.shared
    let menu = ApplicationMenus.make()
    let application = try XCTUnwrap(menu.items.first?.submenu)
    let settings = try XCTUnwrap(application.items.first { $0.keyEquivalent == "," })
    XCTAssertEqual(settings.action, #selector(AppDelegate.showSettings))
    XCTAssertEqual(settings.keyEquivalentModifierMask, .command)
  }

  func testWindowMenuHasNativeKeyboardCommands() throws {
    _ = NSApplication.shared
    let menu = ApplicationMenus.make()
    let windows = try XCTUnwrap(menu.items.first { $0.title == L10n.text("menu.window") }?.submenu)
    let close = try XCTUnwrap(windows.items.first { $0.keyEquivalent == "w" })
    let minimize = try XCTUnwrap(windows.items.first { $0.keyEquivalent == "m" })
    XCTAssertEqual(close.action, #selector(NSWindow.performClose(_:)))
    XCTAssertEqual(minimize.action, #selector(NSWindow.performMiniaturize(_:)))
  }

  func testSectionShortcutsNavigateWithinOneWorkspace() throws {
    _ = NSApplication.shared
    let menu = ApplicationMenus.make()
    let windows = try XCTUnwrap(menu.items.first { $0.title == L10n.text("menu.window") }?.submenu)
    let sections: [(String, Selector)] = [
      ("1", #selector(AppDelegate.showDictation)),
      ("2", #selector(AppDelegate.showFiles)),
      ("3", #selector(AppDelegate.showMeeting)),
      ("4", #selector(AppDelegate.showHistory)),
      ("5", #selector(AppDelegate.showSettings)),
      ("6", #selector(AppDelegate.showAbout)),
    ]
    for (key, action) in sections {
      let item = try XCTUnwrap(windows.items.first { $0.keyEquivalent == key })
      XCTAssertEqual(item.action, action)
      XCTAssertEqual(item.keyEquivalentModifierMask, .command)
    }
  }

  func testAppBundleDoesNotOptOutOfDockAndCommandTab() throws {
    let source = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: source.appendingPathComponent("Resources/App/Info.plist"))
    let object = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    XCTAssertNotEqual(object["LSUIElement"] as? Bool, true)
    XCTAssertEqual(object["CFBundleIdentifier"] as? String, "app.dictlocalai.desktop")
  }

  func testEditingCommandWinsOverCustomDictationShortcutOnlyInsideApp() async throws {
    let keys = Hotkeys()
    keys.toggle = Shortcut(key: 0, modifiers: CGEventFlags.maskCommand.rawValue, label: "Cmd A")
    let toggled = expectation(description: "custom shortcut outside the app")
    var toggles = 0
    keys.onToggle = {
      toggles += 1
      toggled.fulfill()
    }
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
    event.flags = .maskCommand
    keys.isApplicationActive = { true }
    XCTAssertFalse(keys.handle(.keyDown, event))
    let drained = expectation(description: "queued callbacks inside the app completed")
    DispatchQueue.main.async { drained.fulfill() }
    let drainResult = await XCTWaiter.fulfillment(of: [drained], timeout: 1)
    XCTAssertEqual(drainResult, .completed)
    XCTAssertEqual(toggles, 0)
    keys.isApplicationActive = { false }
    XCTAssertTrue(keys.handle(.keyDown, event))
    let toggleResult = await XCTWaiter.fulfillment(of: [toggled], timeout: 1)
    XCTAssertEqual(toggleResult, .completed)
    XCTAssertEqual(toggles, 1)
  }
}
