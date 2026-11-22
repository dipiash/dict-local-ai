from workspace_sources import workspace_source
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
VIEWS = workspace_source()
APP = (ROOT / "Sources/DictLocalAI/App/App.swift").read_text()


class HistoryBoundedViewportTests(unittest.TestCase):
    def setUp(self):
        self.history = VIEWS.split("struct HistoryView: View {")[1].split(
            "private var historyFilter: some View {"
        )[0]

    def test_root_uses_same_finite_viewport_contract_as_files(self):
        self.assertIn("GeometryReader { viewport in", self.history)
        self.assertIn(
            "width: viewport.size.width, height: viewport.size.height, alignment: .topLeading",
            self.history,
        )
        self.assertIn(".padding(AppStyle.pagePadding)", self.history)
        self.assertIn(".frame(maxWidth: .infinity, maxHeight: .infinity)", self.history)
        self.assertLess(
            self.history.index("GeometryReader { viewport in"),
            self.history.index("WorkspaceHeader("),
        )

    def test_independent_history_rail_cannot_measure_entire_workspace(self):
        self.assertIn("HStack(spacing: DesignTokens.Spacing.none) {", self.history)
        self.assertNotIn("HSplitView {", self.history)
        self.assertNotIn("HistorySplitViewportModifier", VIEWS)
        self.assertNotIn("HistoryViewportModifier", VIEWS)
        self.assertNotIn(".clipped()", self.history)
        self.assertIn(".frame(width: DesignTokens.Layout.historySidebarIdealWidth)", self.history)
        self.assertIn(".scrollContentBackground(.hidden)", self.history)
        self.assertIn("Divider()", self.history)
        self.assertIn("TranscriptResultView(", self.history)

    def test_header_and_filter_live_above_panels(self):
        self.assertLess(self.history.index("WorkspaceHeader("), self.history.index("HStack(spacing: DesignTokens.Spacing.none) {"))
        self.assertLess(self.history.index("history-filter-toolbar"), self.history.index("HStack(spacing: DesignTokens.Spacing.none) {"))
        self.assertIn("history-entries-list", self.history)

    def test_filters_selection_and_recording_notifications_stay_active(self):
        self.assertRegex(self.history, r'title:\s*store.entries.isEmpty\s*\? L10n.text\("history.no-records"\)')
        self.assertIn('L10n.text("history.show-all-records")', self.history)
        self.assertIn('requestHistoryChange(.filter(.all))', self.history)
        self.assertIn("get: { store.draftID }", self.history)
        self.assertIn("set: { requestHistoryChange(.selection($0)) }", self.history)
        self.assertIn("store.reload()", self.history)
        self.assertIn(
            "NotificationCenter.default.publisher(for: .recordingStoreDidChange)", self.history,
        )

    def test_app_window_host_remains_unchanged(self):
        self.assertIn("let hostContainer = NSView(", APP)
        self.assertIn("hostingView.sizingOptions = []", APP)


if __name__ == "__main__":
    unittest.main()
