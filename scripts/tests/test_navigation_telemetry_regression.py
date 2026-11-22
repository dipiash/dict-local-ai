from workspace_sources import workspace_source
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
VIEW = workspace_source()
APP = (ROOT / "Sources/DictLocalAI/App/AppServices.swift").read_text()
LOG = (ROOT / "Sources/DictLocalAI/Platform/Diagnostics/DiagnosticLog.swift").read_text()
EVENTS = (ROOT / "Sources/DictLocalAI/Platform/Diagnostics/UsageTelemetry.swift").read_text()
TASK = (ROOT / "Taskfile.yml").read_text()

class NativeNavigationTelemetryContracts(unittest.TestCase):
    def test_no_nested_navigation_split(self):
        self.assertEqual(VIEW.count('NavigationSplitView(columnVisibility:'), 1)
        self.assertNotIn('NavigationSplitView {', VIEW)
        self.assertEqual(VIEW.count('HSplitView {'), 1)
        self.assertIn('HStack(spacing: DesignTokens.Spacing.none) {', VIEW)
        self.assertNotIn('.navigationSplitViewStyle(.balanced)', VIEW)

    def test_root_and_inner_selections_generate_events(self):
        self.assertIn('UsageTelemetry.navigationRequested(to: section, source: .sidebar)', VIEW)
        self.assertIn('UsageTelemetry.settingsRequested(next.telemetryKey)', VIEW)
        self.assertIn('UsageTelemetry.sectionVisible(newSection)', VIEW)
        self.assertIn('UsageTelemetry.sidebarVisibility(', VIEW)
        self.assertIn('UsageTelemetry.navigate(', APP)

    def test_disk_log_can_be_verified_by_native_test(self):
        native = (ROOT / 'Tests/DictMacTests/UsageTelemetryTests.swift').read_text()
        self.assertIn('String(contentsOf: logURL, encoding: .utf8)', native)
        self.assertIn('private(set) var activeLogURL: URL?', LOG)
        self.assertIn('system.info(', LOG)
        self.assertIn('logs:tail:', TASK)
        self.assertIn('settings_requested', EVENTS)

if __name__ == '__main__':
    unittest.main()
