import DictApplication
import XCTest

@testable import DictLocalAI

final class MeetingStopDiagnosticsTests: XCTestCase {
  private struct Failure: Error {}

  func testMeetingStopReasonsHaveStableDiagnosticValues() {
    let codes = [
      MeetingSession.StopCause.requested, .timeLimit, .sleep, .screenLocked, .capture,
      .recognition, .setupCancelled,
    ].map(\.rawValue)
    XCTAssertEqual(
      codes,
      [
        "requested", "time_limit", "sleep", "screen_locked", "capture", "recognition",
        "setup_cancelled",
      ])
  }

  func testWorkflowStopReasonsResolveToDiagnosticCause() {
    typealias Cause = MeetingSession.StopCause
    XCTAssertEqual(Cause(.requested), .requested)
    XCTAssertEqual(Cause(.capture("localized text")), .capture)
    XCTAssertEqual(Cause(.recognition(Failure())), .recognition)
    XCTAssertEqual(Cause(.setupCancelled), .setupCancelled)
  }
}
