from workspace_sources import workspace_source
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'Sources' / 'DictLocalAI'

def text(name):
    return next(iter(APP.rglob(name))).read_text(encoding='utf-8')

class NativeNavigationAndDraftContracts(unittest.TestCase):
    def test_one_navigation_owner_and_independent_history_panel(self):
        source = workspace_source()
        self.assertEqual(source.count('NavigationSplitView(columnVisibility:'), 1)
        self.assertEqual(source.count('HSplitView {'), 1)
        self.assertIn('HStack(spacing: DesignTokens.Spacing.none) {', source)
        self.assertNotIn('NavigationSplitView {', source)
        self.assertNotIn('private func sidebarItem(', source)
        self.assertIn('frame(width: DesignTokens.Layout.settingsSidebarIdealWidth)', source)
        self.assertIn('frame(width: DesignTokens.Layout.historySidebarIdealWidth)', source)
        self.assertIn('history-entries-list', source)

    def test_draft_lives_outside_history_screen(self):
        store = text('HistoryStore.swift')
        self.assertIn('@Published private var draft = HistoryDraft()', store)
        self.assertIn('var draftDirty: Bool { draft.isDirty }', store)
        self.assertIn('func saveDraft()', store)
        self.assertIn('func discardDraft()', store)
        self.assertIn('func editDraftSegment', store)
        view = workspace_source()
        self.assertNotIn('  @State private var document: FileTranscript?', view)
        self.assertIn('requestHistoryChange', view)
        self.assertIn('resolveHistoryChange', view)

    def test_guards_in_window_close_and_quit(self):
        app = text('App.swift')
        self.assertIn('func windowShouldClose(_ sender: NSWindow) -> Bool', app)
        self.assertIn('controller.history.draftDirty', app)
        self.assertIn('controller.history.saveDraft()', app)
        self.assertIn('controller.history.discardDraft()', app)

    def test_keyboard_shortcuts_follow_sidebar_order(self):
        app = text('App.swift')
        for name, command, key in [
            ('menu.dictation-label','showDictation','1'), ('menu.files-label','showFiles','2'),
            ('menu.meetings-label','showMeeting','3'), ('menu.history-label','showHistory','4'),
            ('menu.settings-label','showSettings','5'), ('menu.about-label','showAbout','6')]:
            self.assertIn(f'(L10n.text("{name}"), #selector(AppDelegate.{command}), "{key}")', app)
        self.assertIn('keyEquivalent: ","', app)

    def test_shared_transcript_action_component(self):
        self.assertIn('TranscriptActionBar(', text('FileTranscriptionView.swift'))
        self.assertIn('TranscriptActionBar(', text('MeetingView.swift'))
        self.assertIn('ViewThatFits(in: .horizontal)', text('TranscriptActionBar.swift'))

    def test_no_old_fixed_layout_branch(self):
        source = text('FileTranscriptionView.swift')
        self.assertNotIn('geometry.size.height >= 850', source)
        self.assertNotIn('ViewThatFits(in: .vertical)', source)
        self.assertIn('GeometryReader { viewport in', source)
        self.assertIn('TranscriptActionBar(', source)
        self.assertIn('ViewThatFits(in: .horizontal)', text('TranscriptActionBar.swift'))

if __name__ == '__main__':
    unittest.main()
