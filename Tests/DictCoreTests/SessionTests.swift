import XCTest

@testable import DictCore

@MainActor
final class SessionTests: XCTestCase {
  @MainActor
  func testModesExcludeEachOtherUntilCompletion() async throws {
    let coordinator = ModeCoordinator()
    let dictation = try XCTUnwrap(coordinator.acquire(.dictation))
    XCTAssertNil(coordinator.acquire(.file))
    XCTAssertNil(coordinator.acquire(.meeting))
    coordinator.release(dictation)
    let file = try XCTUnwrap(coordinator.acquire(.file))
    XCTAssertNil(coordinator.acquire(.dictation))
    coordinator.release(file)
    XCTAssertNotNil(coordinator.acquire(.meeting))
  }

  @MainActor
  func testStaleCompletionCannotReleaseNewSessionOfSameMode() async throws {
    let coordinator = ModeCoordinator()
    let old = try XCTUnwrap(coordinator.acquire(.dictation))
    coordinator.release(old)
    let current = try XCTUnwrap(coordinator.acquire(.dictation))
    coordinator.release(old)
    coordinator.release(nil)
    XCTAssertEqual(coordinator.active, .dictation)
    XCTAssertNil(coordinator.acquire(.file))
    coordinator.release(current)
    XCTAssertNotNil(coordinator.acquire(.file))
  }

  func testCancellationIsStickyAndIndependentAcrossSessions() async {
    let cancelled = RecognitionSession()
    let replacement = RecognitionSession()
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<20 { group.addTask { cancelled.cancel() } }
    }
    XCTAssertTrue(cancelled.cancelled)
    XCTAssertFalse(replacement.cancelled)
    cancelled.cancel()
    XCTAssertTrue(cancelled.cancelled)
  }
}
