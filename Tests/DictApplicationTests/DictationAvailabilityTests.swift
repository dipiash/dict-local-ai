import DictApplication
import XCTest

@testable import DictCore

final class DictationAvailabilityTests: XCTestCase {
  @MainActor
  private func workflow(_ modes: ModeCoordinator) -> DictationWorkflow {
    DictationWorkflow(modes: modes, writer: { throw CocoaError(.fileNoSuchFile) })
  }

  @MainActor
  func testActiveMeetingAndImportReportWhyDictationIsBlocked() async {
    let cases: [(ModeCoordinator.Mode, DictationWorkflow.Busy)] = [
      (.meeting, .meeting), (.file, .file),
    ]
    for (mode, expected) in cases {
      let modes = ModeCoordinator()
      let workflow = workflow(modes)
      let lease = modes.acquire(mode)
      XCTAssertNotNil(lease)
      XCTAssertEqual(workflow.busy, expected)
      XCTAssertNil(workflow.start(enabled: true, phase: .idle))
      XCTAssertEqual(workflow.busy.rawValue, mode == .meeting ? "meeting" : "file")
    }
  }

  @MainActor
  func testFreeModeBeginsAndRecordsNoBusyMode() async {
    let modes = ModeCoordinator()
    let workflow = workflow(modes)
    XCTAssertEqual(workflow.busy, .none)
    XCTAssertNotNil(workflow.start(enabled: true, phase: .idle))
    XCTAssertEqual(workflow.busy, .none)
  }
}
