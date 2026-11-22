from workspace_sources import workspace_source
from pathlib import Path
import unittest

VIEWS = workspace_source()


class HistoryStableToolbarTests(unittest.TestCase):
    def test_actions_menu_present_in_both_responsive_variants(self):
        header = VIEWS.split("struct HistoryView: View {")[1].split("if let error = store.error")[0]
        self.assertIn("ViewThatFits(in: .horizontal)", header)
        self.assertEqual(header.count("historyFilter"), 2)
        self.assertEqual(header.count("historyActionMenu"), 2)
        self.assertNotIn("historyActions", header)

    def test_selection_only_changes_enablement_not_toolbar_geometry(self):
        history = VIEWS.split("struct HistoryView: View {")[1]
        menu = history.split("private var historyActionMenu: some View {")[1].split("private func requestHistoryChange")[0]
        self.assertIn('Menu(L10n.text("history.record-actions"))', menu)
        self.assertIn('.disabled(store.draftDocument == nil || selected == nil)', menu)
        self.assertIn('history-record-actions', menu)
        self.assertNotIn('if let document = store.draftDocument, selected != nil {\n      Menu', menu)

    def test_selection_does_not_toggle_separator_or_second_toolbar_row(self):
        header = VIEWS.split("struct HistoryView: View {")[1].split("if let error = store.error")[0]
        self.assertNotIn('if selected != nil', header)
        self.assertNotIn('if store.draftDocument != nil', header)
        self.assertIn('history-filter-toolbar', header)


if __name__ == "__main__":
    unittest.main()
