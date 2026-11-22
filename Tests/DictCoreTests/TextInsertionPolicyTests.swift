import DictCore
import XCTest

final class TextInsertionPolicyTests: XCTestCase {
  func testGroupRequiresExplicitEditableTraitAndTextSelectionCapability() {
    XCTAssertFalse(TextInsertionPolicy.accepts(.init(role: "AXGroup", secure: false)))
    XCTAssertFalse(
      TextInsertionPolicy.accepts(
        .init(
          role: "AXGroup", secure: false, selectedTextWritable: true)))
    XCTAssertFalse(
      TextInsertionPolicy.accepts(
        .init(
          role: "AXGroup", secure: false, editable: true)))
    XCTAssertTrue(
      TextInsertionPolicy.accepts(
        .init(
          role: "AXGroup", secure: false, editable: true, selectionWritable: true)))
    XCTAssertTrue(
      TextInsertionPolicy.accepts(
        .init(
          role: "AXGroup", secure: false, editable: true, focused: true)))
    XCTAssertTrue(
      TextInsertionPolicy.accepts(
        .init(
          role: "AXWebArea", secure: false, editable: true, focused: true)))
    XCTAssertFalse(
      TextInsertionPolicy.accepts(
        .init(
          role: "AXWebArea", secure: false, editable: true)))
  }

  func testSecureDisabledReadOnlyAndUnrelatedRolesAreRejected() {
    for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXGroup"] {
      XCTAssertFalse(
        TextInsertionPolicy.accepts(
          .init(
            role: role, secure: true, editable: true, selectedTextWritable: true)))
      XCTAssertFalse(
        TextInsertionPolicy.accepts(
          .init(
            role: role, secure: false, enabled: false, editable: true, selectedTextWritable: true)))
      XCTAssertFalse(
        TextInsertionPolicy.accepts(
          .init(
            role: role, secure: false, editable: false, selectedTextWritable: true)))
    }
    XCTAssertFalse(
      TextInsertionPolicy.accepts(
        .init(
          role: "AXButton", secure: false, editable: true, selectedTextWritable: true)))
    XCTAssertTrue(TextInsertionPolicy.accepts(.init(role: "AXTextArea", secure: false)))
  }

  func testBrowserAndWebContentUsePasteRatherThanAnAccessibilityWrite() {
    XCTAssertTrue(
      TextInsertionPolicy.prefersPaste(webContent: true, bundleIdentifier: "unknown.app"))
    XCTAssertTrue(
      TextInsertionPolicy.prefersPaste(webContent: false, bundleIdentifier: "com.google.Chrome"))
    XCTAssertTrue(
      TextInsertionPolicy.prefersPaste(
        webContent: false, bundleIdentifier: "com.apple.Safari.TechnologyPreview"))
    XCTAssertFalse(
      TextInsertionPolicy.prefersPaste(webContent: false, bundleIdentifier: "com.apple.TextEdit"))
    XCTAssertFalse(
      TextInsertionPolicy.prefersPaste(
        webContent: false, bundleIdentifier: "com.google.ChromeImpersonator"))
  }

  func testPasteSupportsRecreatedEditorAndUnknownAXWindow() {
    XCTAssertTrue(
      TextInsertionPolicy.mayPaste(
        sameProcess: true, sameWindow: true, bothWindowsKnown: true, secure: false))
    XCTAssertTrue(
      TextInsertionPolicy.mayPaste(
        sameProcess: true, sameWindow: false, bothWindowsKnown: false, secure: false))
    XCTAssertFalse(
      TextInsertionPolicy.mayPaste(
        sameProcess: true, sameWindow: false, bothWindowsKnown: true, secure: false))
    XCTAssertFalse(
      TextInsertionPolicy.mayPaste(
        sameProcess: false, sameWindow: true, bothWindowsKnown: true, secure: false))
    XCTAssertFalse(
      TextInsertionPolicy.mayPaste(
        sameProcess: true, sameWindow: true, bothWindowsKnown: true, secure: true))
  }

  func testDeliveryRequiresSameProcessSameElementAndEligibleFocus() {
    XCTAssertTrue(
      TextInsertionPolicy.mayDeliver(sameProcess: true, sameElement: true, eligible: true))
    XCTAssertFalse(
      TextInsertionPolicy.mayDeliver(sameProcess: false, sameElement: true, eligible: true))
    XCTAssertFalse(
      TextInsertionPolicy.mayDeliver(sameProcess: true, sameElement: false, eligible: true))
    XCTAssertFalse(
      TextInsertionPolicy.mayDeliver(sameProcess: true, sameElement: true, eligible: false))
    XCTAssertTrue(
      TextInsertionPolicy.mayDeliver(
        sameProcess: true, sameElement: false, matchingIdentifier: true, eligible: true))
    XCTAssertFalse(
      TextInsertionPolicy.mayDeliver(
        sameProcess: false, sameElement: false, matchingIdentifier: true, eligible: true))
    XCTAssertFalse(
      TextInsertionPolicy.mayDeliver(
        sameProcess: true, sameElement: false, matchingIdentifier: true, eligible: false))
  }
}
