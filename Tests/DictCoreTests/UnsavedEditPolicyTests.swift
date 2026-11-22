import XCTest

@testable import DictCore

final class UnsavedEditPolicyTests: XCTestCase {
  func testDirtyNavigationRequiresConfirmation() {
    XCTAssertTrue(UnsavedEditPolicy.requiresConfirmation(dirty: true, changesContext: true))
  }
  func testActivationOrUnmodifiedDocumentNeedsNoConfirmation() {
    XCTAssertFalse(UnsavedEditPolicy.requiresConfirmation(dirty: true, changesContext: false))
    XCTAssertFalse(UnsavedEditPolicy.requiresConfirmation(dirty: false, changesContext: true))
  }
}
