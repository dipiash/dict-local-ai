from workspace_sources import workspace_source
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2] / "Sources" / "DictLocalAI"
VIEWS = workspace_source()
FILES = (ROOT / "Features/Files/FileTranscriptionView.swift").read_text()
DICTATION = (ROOT / "Features/Dictation/DictationSession.swift").read_text()
INSERT = (ROOT / "Platform/Input/TextInsertion.swift").read_text()
TELEMETRY = (ROOT / "Platform/Diagnostics/UsageTelemetry.swift").read_text()


class LayoutContractTests(unittest.TestCase):
    def test_settings_has_one_inner_rail_with_seven_sections(self):
        for name in ("general", "permissions", "models", "shortcuts", "microphone", "storage", "startup"):
            self.assertIn(f"case .{name}", VIEWS)
        self.assertIn('accessibilityIdentifier("settings-navigation")', VIEWS)
        self.assertNotIn('Picker("Раздел настроек"', VIEWS)

    def test_settings_default_general_not_forced_models(self):
        self.assertIn("@State private var settingsTab = SettingsTab.general", VIEWS)
        self.assertIn("if newSection == .settings { settingsTab = .general }", VIEWS)
        self.assertNotIn("if !controller.ready { settingsTab = .models }", VIEWS)

    def test_shortcuts_microphone_privacy_and_storage_occupy_separate_pages(self):
        for component in ("private var shortcutsSettings", "private var microphoneSettings",
                          "private var permissionsSettings", "private var storageSettings", "private var startupSettings"):
            self.assertIn(component, VIEWS)

    def test_dictation_has_editable_persistent_scratchpad_and_focus(self):
        self.assertIn("@Published var scratchpad", DICTATION)
        self.assertIn("TextEditor(text: $controller.scratchpad)", VIEWS)
        self.assertIn("controller.internalEditorFocused = focused", VIEWS)
        self.assertIn("controller.scratchpad.isEmpty", VIEWS)
        self.assertIn("local_editor_inserted", INSERT)
        self.assertIn("insertInFocusedLocalEditor", DICTATION)
        self.assertIn("fallback_clipboard", DICTATION)
        self.assertIn("duration: .seconds(6), preserveResult: true", DICTATION)

    def test_dictation_uses_one_editor_and_no_duplicate_result_panel(self):
        section = VIEWS.split('struct DictationWorkspaceView: View {')[1].split('struct WorkspaceView: View {')[0]
        self.assertIn('TextEditor(text: $controller.scratchpad)', section)
        self.assertIn('dictation.speak-or-type-here', section)
        self.assertIn('.allowsHitTesting(false)', section)
        self.assertNotIn('private var resultPanel', section)
        self.assertNotIn('dictation-result-panel', section)
        self.assertNotIn('В редактор', section)
        self.assertNotIn('Скрыть результат', section)
        self.assertNotIn('Подробная транскрипция', section)
        self.assertIn('Menu(L10n.text("dictation.export"))', section)
        self.assertLess(section.index('Menu(L10n.text("dictation.export"))'), section.index('TextEditor(text: $controller.scratchpad)'))

    def test_dictation_keeps_original_bounded_geometry_viewport(self):
        section = VIEWS.split('struct DictationWorkspaceView: View {')[1].split('struct WorkspaceView: View {')[0]
        self.assertIn('GeometryReader { geometry in', section)
        self.assertIn('frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)', section)
        self.assertNotIn('.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)', section)
        app = (ROOT / 'App/App.swift').read_text()
        self.assertIn('let hostContainer = NSView(', app)
        self.assertIn('hostingView.sizingOptions = []', app)

    def test_about_compact_spacing_and_history_feature(self):
        section = VIEWS.split('private var about: some View {')[1].split('private var permissionsSettings: some View {')[0]
        self.assertIn('title: L10n.text("menu.history-label")', section)
        self.assertIn('settings.text-is-stored-locally-for', section)
        self.assertIn('settings.the-app-source-code-is', section)
        self.assertIn('.padding(.vertical, DesignTokens.Spacing.s)', section)

    def test_shortcuts_come_from_live_preferences(self):
        section = VIEWS.split('struct DictationWorkspaceView: View {')[1].split('struct WorkspaceView: View {')[0]
        self.assertIn('@ObservedObject var preferences: Preferences', section)
        self.assertIn('preferences.toggle.displayLabel', section)
        self.assertIn('preferences.hold.displayLabel', section)
        self.assertIn('DictationWorkspaceView(controller: controller.dictation, preferences: preferences)', VIEWS)

    def test_dictation_instructions_are_multiline_and_hold_first(self):
        section = VIEWS.split('struct DictationWorkspaceView: View {')[1].split('struct WorkspaceView: View {')[0]
        self.assertIn('dictation.editor-instructions', section)
        self.assertLess(section.index('preferences.hold.displayLabel'), section.index('preferences.toggle.displayLabel'))
        self.assertIn('subtitle: shortcutHint', section)

    def test_escape_hint_only_on_hands_free_recording_next_to_close(self):
        recording = VIEWS.split('struct RecordingView: View {')[1].split('struct DictationWorkspaceView: View {')[0]
        self.assertIn('if controller.phase == .recording && controller.handsFree {', recording)
        self.assertEqual(recording.count('Text(L10n.text("recording.esc-cancel"))'), 1)
        self.assertLess(recording.index('Text(L10n.text("recording.esc-cancel"))'), recording.index('Image(systemName: "xmark")'))
        self.assertIn('TranscriptResultView(transcript: transcript)', recording)
        self.assertIn('controller.elapsed % 60', recording)

    def test_workspace_pages_use_consistent_headers_and_subtitles(self):
        meeting = (ROOT / 'Features/Meetings/MeetingView.swift').read_text()
        shared = (ROOT / 'Shared/Components/WorkspaceComponents.swift').read_text()
        self.assertRegex(FILES, r'WorkspaceHeader\(\s*title: L10n.text\("menu.files-label"\),\s*subtitle:')
        self.assertRegex(meeting, r'title: L10n.text\("menu.meetings-label"\),\s*subtitle:')
        self.assertRegex(VIEWS, r'title: L10n.text\("menu.history-label"\),\s*subtitle:')
        self.assertIn('WorkspaceHeader(title: title, subtitle: subtitle)', shared)
        for title in ('settings.general', 'settings.permissions', 'settings.shortcuts', 'settings.microphone', 'settings.storage', 'settings.startup'):
            self.assertRegex(VIEWS, rf'SettingsFormPage\(\s*title:\s*L10n.text\("{title}"\),\s*subtitle:')
        self.assertRegex((ROOT / 'Features/Settings/ModelsView.swift').read_text(), r'SettingsFormPage\(\s*title: L10n.text\("settings.models"\),\s*subtitle:')

    def test_dictation_export_has_distinct_formats_and_other_exports_unchanged(self):
        exporter = (ROOT / 'Platform/Storage/TranscriptExporter.swift').read_text()
        self.assertIn('static func savePlainText', exporter)
        self.assertIn('Data(text.utf8)', exporter)
        self.assertIn('transcript.plainText.utf8', exporter)
        self.assertIn('transcript.json()', exporter)
        self.assertIn('case "txt":', DICTATION)
        self.assertIn('scratchpad.isEmpty ? text : scratchpad', DICTATION)
        self.assertIn('TranscriptExporter.savePlainText', DICTATION)
        self.assertIn('case "json":', DICTATION)
        self.assertIn('TranscriptExporter.save(transcript, format: "json"', DICTATION)
        section = VIEWS.split('struct DictationWorkspaceView: View {')[1].split('struct WorkspaceView: View {')[0]
        self.assertIn('dictation.the-latest-dictation-with-timestamps', section)
        self.assertIn('controller.copyResult()', section)
        self.assertIn('TextInsertion.copy(controller.scratchpad)', section)
        self.assertIn('Button(L10n.text("dictation.process-again"))', section)
        self.assertIn('Button(L10n.text("dictation.delete-recording"), role: .destructive)', section)

    def test_primary_sidebar_has_no_duplicate_app_name(self):
        workspace = VIEWS.split('struct WorkspaceView: View {')[1].split('struct HistoryView: View {')[0]
        self.assertNotIn('Section("Dict Local AI")', workspace)
        self.assertIn('List(', workspace)

    def test_history_rail_has_rounded_clipped_panel_without_width_shift(self):
        history = VIEWS.split('struct HistoryView: View {')[1]
        self.assertIn('.scrollContentBackground(.hidden)', history)
        self.assertIn('RoundedRectangle(cornerRadius: DesignTokens.Radius.panel', history)
        self.assertIn('.clipShape(', history)
        self.assertIn('.frame(width: DesignTokens.Layout.historySidebarIdealWidth)', history)

    def test_settings_navigation_uses_centered_symbol_and_split_storage(self):
        self.assertIn('Label(tab.title, systemImage: tab.symbol)', VIEWS)
        self.assertIn('HSplitView {', VIEWS)
        self.assertIn('.listStyle(.sidebar)', VIEWS)
        self.assertIn('case storage', VIEWS)
        self.assertIn('case startup', VIEWS)

    def test_file_transcript_fills_tall_window_short_window_scrolls(self):
        self.assertNotIn("ViewThatFits(in: .vertical)", FILES)
        self.assertNotIn("geometry.size.height >= 850", FILES)
        self.assertIn("GeometryReader { viewport in", FILES)
        self.assertIn("transcriptPane(", FILES)
        self.assertIn("height: max(", FILES)
        self.assertIn("DesignTokens.Layout.transcriptViewportFraction", FILES)
        self.assertIn('accessibilityIdentifier("files-page-scroll")', FILES)

    def test_file_export_and_timestamps_are_outside_page_scroll(self):
        body = FILES.split("private var fileControls")[0]
        self.assertIn("      footer\n", body)
        self.assertIn('accessibilityIdentifier("file-export-footer")', FILES)
        self.assertIn("files.timestamps-are-approximate-and-start", FILES)

    def test_history_actions_align_with_filter_not_bottom_of_editor(self):
        segment = VIEWS.split('struct HistoryView: View {')[1]
        self.assertIn('ViewThatFits(in: .horizontal)', segment)
        self.assertIn('historyFilter', segment)
        self.assertNotIn('historyActions', segment)
        self.assertEqual(segment.split('private var historyActionMenu:')[0].count('historyActionMenu'), 2)
        self.assertIn('.disabled(store.draftDocument == nil || selected == nil)', segment)
        self.assertIn('history-filter-toolbar', segment)
        self.assertIn('HStack(spacing: DesignTokens.Spacing.none) {', segment)
        self.assertNotIn('HSplitView {', segment)

    def test_usage_logging_includes_new_settings_tabs_and_editor_actions(self):

        for choice in ("permissions", "models", "shortcuts", "microphone", "storage", "startup"):
            self.assertIn(f'"{choice}"', TELEMETRY)
        self.assertIn("exportTXT", TELEMETRY)
        self.assertIn("exportJSON", TELEMETRY)
        self.assertIn("clearScratchpad", TELEMETRY)


if __name__ == "__main__":
    unittest.main()
