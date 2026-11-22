import XCTest

@testable import DictCore

final class AppRouterTests: XCTestCase {
  func testFirstLaunchDefaultsToSettings() {
    var navigation = AppRouter()
    XCTAssertEqual(navigation.selected, .settings)
    XCTAssertFalse(navigation.isOpen)
    navigation.reopen()
    XCTAssertTrue(navigation.isOpen)
    XCTAssertEqual(navigation.selected, .settings)
  }

  func testExplicitMenuNavigationUsesSameWindowState() {
    var navigation = AppRouter()
    for section in WorkspaceSection.allCases {
      navigation.request(section, historyHasUnsavedEdits: false)
      XCTAssertTrue(navigation.isOpen)
      XCTAssertEqual(navigation.selected, section)
    }
  }

  func testDockActivationDoesNotResetOpenSection() {
    var navigation = AppRouter()
    navigation.request(.meeting, historyHasUnsavedEdits: false)
    navigation.reopen()
    navigation.reopen()
    XCTAssertEqual(navigation.selected, .meeting)
  }

  func testClosedWindowReopensInSettings() {
    var navigation = AppRouter()
    navigation.request(.files, historyHasUnsavedEdits: false)
    navigation.close()
    XCTAssertEqual(navigation.selected, .files)
    XCTAssertFalse(navigation.isOpen)
    navigation.reopen()
    XCTAssertEqual(navigation.selected, .settings)
  }

  func testExplicitTraySelectionAfterCloseOverridesDefault() {
    var navigation = AppRouter()
    navigation.request(.history, historyHasUnsavedEdits: false)
    navigation.close()
    navigation.request(.about, historyHasUnsavedEdits: false)
    XCTAssertEqual(navigation.selected, .about)
    XCTAssertTrue(navigation.isOpen)
  }

  func testDirtyHistoryRequestDoesNotChangeSectionUntilConfirmation() {
    var navigation = AppRouter()
    navigation.request(.history, historyHasUnsavedEdits: false)
    let outcome = navigation.request(.files, historyHasUnsavedEdits: true)
    XCTAssertEqual(outcome, .confirmationRequired)
    XCTAssertEqual(navigation.selected, .history)
    XCTAssertEqual(navigation.pendingSection, .files)
    XCTAssertTrue(navigation.isOpen)
    XCTAssertEqual(
      navigation.confirmPending(), .navigated(from: .history, to: .files))
    XCTAssertNil(navigation.pendingSection)
  }

  func testCancelPendingHistoryNavigationKeepsSelection() {
    var navigation = AppRouter()
    navigation.request(.history, historyHasUnsavedEdits: false)
    navigation.request(.settings, historyHasUnsavedEdits: true)
    navigation.cancelPending()
    XCTAssertNil(navigation.pendingSection)
    XCTAssertNil(navigation.confirmPending())
    XCTAssertEqual(navigation.selected, .history)
  }

  func testNavigatingWithinHistoryDoesNotPromptForDirtyDraft() {
    var navigation = AppRouter()
    navigation.request(.history, historyHasUnsavedEdits: false)
    XCTAssertEqual(
      navigation.request(.history, historyHasUnsavedEdits: true),
      .navigated(from: .history, to: .history))
    XCTAssertNil(navigation.pendingSection)
  }

  func testDraftDoesNotBlockLeavingOtherSections() {
    var navigation = AppRouter()
    navigation.request(.meeting, historyHasUnsavedEdits: false)
    XCTAssertEqual(
      navigation.request(.files, historyHasUnsavedEdits: true),
      .navigated(from: .meeting, to: .files))
  }

  func testPendingDestinationCanBeReplacedBeforeConfirmation() {
    var navigation = AppRouter()
    navigation.request(.history, historyHasUnsavedEdits: false)
    navigation.request(.files, historyHasUnsavedEdits: true)
    navigation.request(.about, historyHasUnsavedEdits: true)
    XCTAssertEqual(navigation.pendingSection, .about)
    XCTAssertEqual(navigation.selected, .history)
    XCTAssertEqual(
      navigation.confirmPending(), .navigated(from: .history, to: .about))
  }

  func testReopenReportsRealPreviousAndNewSections() {
    var navigation = AppRouter()
    navigation.request(.files, historyHasUnsavedEdits: false)
    XCTAssertEqual(navigation.reopen(), .navigated(from: .files, to: .files))
    navigation.close()
    XCTAssertEqual(navigation.reopen(), .navigated(from: .files, to: .settings))
  }

}
