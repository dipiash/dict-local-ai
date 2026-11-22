import XCTest

@testable import DictCore

final class QuitConfirmationPolicyTests: XCTestCase {
  func testIdleAppQuitsWithoutConfirmation() {
    let policy = QuitConfirmationPolicy(
      fileRunning: false, fileUnsaved: false, meetingRunning: false,
      meetingUnsaved: false, dictationBusy: false)
    XCTAssertFalse(policy.requiresConfirmation)
    XCTAssertNil(policy.preferredSection)
  }

  func testFileProcessingRaisesFilesBeforePrompt() {
    let policy = QuitConfirmationPolicy(
      fileRunning: true, fileUnsaved: false, meetingRunning: false,
      meetingUnsaved: false, dictationBusy: false)
    XCTAssertTrue(policy.requiresConfirmation)
    XCTAssertEqual(policy.preferredSection, .files)
  }

  func testCompletedButUnsavedTranscriptStillPrompts() {
    let policy = QuitConfirmationPolicy(
      fileRunning: false, fileUnsaved: true, meetingRunning: false,
      meetingUnsaved: false, dictationBusy: false)
    XCTAssertEqual(policy.preferredSection, .files)
  }

  func testRecordingOrUnsavedMeetingTakesPriority() {
    let policy = QuitConfirmationPolicy(
      fileRunning: false, fileUnsaved: true, meetingRunning: false,
      meetingUnsaved: true, dictationBusy: false)
    XCTAssertEqual(policy.preferredSection, .meeting)
  }

  func testActiveDictationIsProtectedToo() {
    let policy = QuitConfirmationPolicy(
      fileRunning: false, fileUnsaved: false, meetingRunning: false,
      meetingUnsaved: false, dictationBusy: true)
    XCTAssertEqual(policy.preferredSection, .dictation)
  }
}
