from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
FILES = (ROOT / "Sources/DictLocalAI/Features/Files/FileTranscriptionView.swift").read_text()
TOKENS = (ROOT / "Sources/DictLocalAI/Shared/DesignSystem/DesignTokens.swift").read_text()


class FilesRenderRegressionTests(unittest.TestCase):
    def test_file_page_has_one_finite_scroll_layout(self):
        self.assertIn("GeometryReader { viewport in", FILES)
        self.assertIn("ScrollView(.vertical)", FILES)
        self.assertNotIn("ViewThatFits(in: .vertical)", FILES)
        self.assertNotIn("Spacer(minLength: 0)", FILES)
        self.assertIn('accessibilityIdentifier("files-page-scroll")', FILES)
        self.assertIn("viewport.size.height * DesignTokens.Layout.transcriptViewportFraction", FILES)
        self.assertIn("static let transcriptViewportFraction", TOKENS)

    def test_export_footer_is_outside_page_scroll(self):
        self.assertLess(FILES.index(".scrollIndicators(.visible)"), FILES.index("        footer"))
        self.assertIn('accessibilityIdentifier("file-export-footer")', FILES)

    def test_file_screen_exposes_lifecycle_logs_and_real_content(self):
        self.assertIn('"files-ui", "page_appeared"', FILES)
        self.assertIn('"files-ui", "page_disappeared"', FILES)
        smoke = (ROOT / "scripts/development/ui-smoke-macos.sh").read_text()
        self.assertIn("repeat 3 times", smoke)
        self.assertIn("Files after repeat navigation", smoke)

if __name__ == "__main__":
    unittest.main()
