from workspace_sources import workspace_source
from pathlib import Path
import unittest
import re

ROOT = Path(__file__).resolve().parents[2] / "Sources" / "DictLocalAI"


class SettingsConsistencyTests(unittest.TestCase):
    def test_page_title_section_title_and_card_share_one_column(self):
        shared = (ROOT / "Shared/Components/WorkspaceComponents.swift").read_text()
        self.assertIn("struct SettingsFormPage<Content: View>", shared)
        self.assertIn("struct SettingsSection<Content: View>", shared)
        self.assertIn("VStack(alignment: .leading, spacing: DesignTokens.Spacing.l)", shared)
        self.assertIn(".padding(.horizontal, DesignTokens.Spacing.page)", shared)
        self.assertIn(".padding(DesignTokens.Spacing.m)", shared)
        self.assertIn("DesignTokens.Colors.surface", shared)
        self.assertNotIn("Form { content }", shared)

    def test_no_screen_image_permission_copy_in_ui(self):
        views = workspace_source()
        self.assertNotIn("Доступ к изображению экрана не требуется", views)
        self.assertIn("settings.macos-asks-for-access-the", views)

    def test_seven_settings_pages_use_shared_sections(self):
        views = workspace_source()
        models = (ROOT / "Features/Settings/ModelsView.swift").read_text()
        self.assertEqual(len(re.findall(r'SettingsFormPage\(\s*title: L10n.text\("', views)), 6)
        self.assertEqual(len(re.findall(r'SettingsFormPage\(\s*title: L10n.text\("', models)), 1)
        self.assertGreaterEqual(views.count('SettingsSection('), 7)
        self.assertEqual(models.count('SettingsSection('), 3)

    def test_toggle_controls_use_same_trailing_switch_row(self):
        views = workspace_source()
        shared = (ROOT / "Shared/Components/WorkspaceComponents.swift").read_text()
        self.assertRegex(views, r'SettingsToggleRow\(\s*title: L10n.text\("menu.dictation-enabled"\)')
        self.assertIn('title: L10n.text("settings.keep-text-for-the-last")', views)
        self.assertIn('title: L10n.text("settings.open-at-login")', views)
        self.assertIn(".toggleStyle(.switch)", shared)


if __name__ == "__main__":
    unittest.main()
