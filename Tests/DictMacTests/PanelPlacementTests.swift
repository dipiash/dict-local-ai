import XCTest

@testable import DictLocalAI

#if canImport(CoreGraphics)
  import CoreGraphics
#endif

final class PanelPlacementTests: XCTestCase {
  func testGrowingPanelStaysAboveDockAndInsideScreen() {
    let visible = CGRect(x: 0, y: 70, width: 1440, height: 800)
    let frame = CGRect(x: 1200, y: -100, width: 500, height: 300)
    let result = PanelPlacement.fitted(frame, within: visible)
    XCTAssertEqual(result, CGRect(x: 940, y: 70, width: 500, height: 300))
  }

  func testNegativeMonitorCoordinatesAndOversizedContent() {
    let visible = CGRect(x: -1280, y: -900, width: 1280, height: 880)
    let result = PanelPlacement.fitted(
      CGRect(x: -1300, y: -1000, width: 1500, height: 1000), within: visible)
    XCTAssertEqual(result, visible)
  }

  func testValidDraggedPositionIsPreserved() {
    let frame = CGRect(x: 250, y: 200, width: 500, height: 200)
    XCTAssertEqual(
      PanelPlacement.fitted(frame, within: CGRect(x: 0, y: 40, width: 1400, height: 900)), frame)
  }
}
