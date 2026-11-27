import DictApplication
import XCTest

@testable import DictLocalAI

final class DictationBlockedMessageTests: XCTestCase {
  @MainActor
  func testDictationNoticeNamesTheActiveWorkflow() {
    XCTAssertEqual(DictationSession.blockedDictationMessageKey(.meeting), "dictation.busy-meeting")
    XCTAssertEqual(DictationSession.blockedDictationMessageKey(.file), "dictation.busy-file")
    XCTAssertNil(DictationSession.blockedDictationMessageKey(.none))
  }
}
