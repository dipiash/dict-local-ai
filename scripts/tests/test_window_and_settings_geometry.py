from workspace_sources import workspace_source
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2] / "Sources" / "DictLocalAI"


def code(name: str) -> str:
    return next(iter(ROOT.rglob(name))).read_text(encoding="utf-8")


class WindowAndSettingsGeometry(unittest.TestCase):
    def test_window_does_not_derive_constraints_from_changing_swiftui_tab(self):
        app = code("App.swift")
        self.assertIn("hostingView.sizingOptions = []", app)
        self.assertIn("window.contentMinSize = NSSize(", app)
        self.assertIn("window.contentView = hostContainer", app)
        self.assertIn("hostContainer.addSubview(hostingView)", app)
        self.assertIn("hostingView.translatesAutoresizingMaskIntoConstraints = false", app)
        for anchor in ("leadingAnchor", "trailingAnchor", "topAnchor", "bottomAnchor"):
            self.assertIn(f"hostingView.{anchor}.constraint(equalTo: hostContainer.{anchor})", app)
        self.assertIn('"window", "workspace_size_policy"', app)
        self.assertIn('"workspace_host_ready"', app)
        self.assertIn('"workspace_host_zero_bounds"', app)
        self.assertNotIn("window.contentView = NSHostingView(", app)
        self.assertNotIn("window.contentView = hostingView", app)
        self.assertIn('"window", "workspace_resize_outside_drag"', app)
        self.assertIn('"window", "workspace_resize_by_user"', app)

    def test_native_smoke_checks_real_content_not_only_window_title(self):
        script = Path(__file__).resolve().parents[2] / "scripts" / "development" / "ui-smoke-macos.sh"
        source = script.read_text(encoding="utf-8")
        self.assertIn("entire contents of front window", source)
        self.assertIn("requireRenderedText", source)
        for title in ("Редактор диктовки", "Преобразуйте аудиофайлы в текст", "Основные", "Dictation Editor", "General"):
            self.assertIn(title, source)
        self.assertIn('error "Blank or unrendered workspace:', source)
        self.assertIn('"Преобразуйте аудиофайлы в текст", "Files after repeat navigation"', source)
        self.assertIn('repeat 3 times', source)

    def test_native_geometry_smoke_is_automated_for_mac(self):
        script = Path(__file__).resolve().parents[2] / "scripts" / "development" / "ui-window-geometry-macos.sh"
        source = script.read_text(encoding="utf-8")
        self.assertIn('keystroke "2" using {command down}', source)
        self.assertIn('keystroke "4" using {command down}', source)
        self.assertIn('keystroke "5" using {command down}', source)
        self.assertIn('First vertical resize', source)
        self.assertIn('set size of front window to originalSize', source)

    def test_history_list_and_settings_list_have_stable_widths(self):
        views = workspace_source()
        self.assertIn(".frame(width: DesignTokens.Layout.historySidebarIdealWidth)", views)
        self.assertIn(".frame(width: DesignTokens.Layout.settingsSidebarIdealWidth)", views)
        self.assertNotIn("idealWidth: DesignTokens.Layout.historySidebarIdealWidth", views)

    def test_every_settings_page_uses_one_aligned_section_grammar(self):
        views = workspace_source()
        models = code("ModelsView.swift")
        shared = code("WorkspaceComponents.swift")
        for name in ("settings.general", "settings.permissions", "settings.shortcuts", "settings.microphone", "settings.storage", "settings.startup"):
            self.assertRegex(views, rf'SettingsFormPage\(\s*title:\s*L10n.text\("{name}"\),\s*subtitle:')
        self.assertRegex(models, r'SettingsFormPage\(\s*title: L10n.text\("settings.models"\),\s*subtitle:')
        self.assertIn("WorkspaceHeader(title: title, subtitle: subtitle)", shared)
        self.assertIn("struct SettingsSection<Content: View>", shared)
        self.assertIn("struct SettingsToggleRow: View", shared)
        self.assertIn("ScrollView(.vertical)", shared)
        self.assertIn(".frame(maxWidth: DesignTokens.Layout.settingsContentMaximumWidth", shared)
        self.assertNotIn("Form { content }", shared)
        self.assertNotIn(".formStyle(.grouped)", shared)
        for title in ("menu.dictation-label", "settings.readiness", "settings.hold-to-record", "menu.hands-free-recording", "settings.recording-source", "menu.history-label", "settings.open-at-login-label"):
            self.assertIn(f'SettingsSection(L10n.text("{title}"))', views)
        for title in ("Parakeet Ultra", "Nemotron 3 · fast32 + fast128"):
            self.assertIn(f'SettingsSection("{title}")', models)
        self.assertIn('SettingsSection(L10n.text("models.status"))', models)
        self.assertIn('SettingsSection(L10n.text("settings.access-status"))', views)
        self.assertNotIn("Доступ к изображению экрана не требуется", views)
        for title in ("settings.general", "settings.shortcuts", "settings.microphone", "settings.storage", "settings.startup"):
            self.assertNotIn(f'Text("{title}").font(AppStyle.title)', views)
        self.assertNotIn('GroupBox("Разрешения")', views)

    def test_meeting_capture_uses_only_the_system_audio_tap(self):
        meeting = code("MeetingView.swift")
        session = code("MeetingSession.swift")
        self.assertIn('accessibilityIdentifier("meeting-system-audio-only")', meeting)
        self.assertNotIn('Picker("Записывать"', meeting)
        capture = code("MeetingAudioCapture.swift")
        self.assertIn("try await capture.start()", session)
        self.assertIn("SystemAudioTapCapture(", capture)
        for unsupported in ("AVCaptureDevice", "AVAudioEngine", "microphoneID", "MeetingAudioSource"):
            self.assertNotIn(unsupported, capture + session)
        self.assertNotIn("MeetingChannelDeduplicator", code("MeetingRecognitionPipeline.swift"))
        self.assertIn("meeting.records-only-audio-playing-on", meeting)


if __name__ == "__main__":
    unittest.main()
