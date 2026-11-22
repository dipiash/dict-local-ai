import Foundation
import XCTest

@testable import DictLocalAI

@MainActor
final class UsageTelemetryTests: XCTestCase {
  func testNavigationAndSettingsEventsActuallyReachTheSessionLog() throws {
    let log = DiagnosticLog.shared
    let logURL = try XCTUnwrap(log.activeLogURL, "Cannot write session log to Library/Logs")

    UsageTelemetry.navigationRequested(to: .files, source: .sidebar)
    UsageTelemetry.navigate(from: .settings, to: .files, source: .sidebar, changed: true)
    UsageTelemetry.settingsRequested("microphone")
    UsageTelemetry.sectionVisible(.files)
    UsageTelemetry.sidebarVisibility("hidden")

    let contents = try String(contentsOf: logURL, encoding: .utf8)
    XCTAssertTrue(contents.contains("[usage] navigation_requested to=files source=sidebar"))
    XCTAssertTrue(
      contents.contains("[usage] navigation from=settings to=files source=sidebar changed=true"))
    XCTAssertTrue(contents.contains("[usage] settings_requested tab=microphone"))
    XCTAssertTrue(contents.contains("[usage] section_selected section=files"))
    XCTAssertTrue(contents.contains("[usage] sidebar_visibility state=hidden"))
  }
}
