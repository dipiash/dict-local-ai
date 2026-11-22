from workspace_sources import workspace_source
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class WorkspaceScrollingTests(unittest.TestCase):
    def test_file_page_scrolls_independently_of_transcript(self):
        source = (ROOT / 'Sources/DictLocalAI/Features/Files/FileTranscriptionView.swift').read_text()
        self.assertIn('ScrollView(.vertical) {', source)
        self.assertIn('.frame(maxWidth: .infinity, maxHeight: .infinity)', source)
        self.assertIn('.scrollIndicators(.visible)', source)
        self.assertIn('TranscriptResultView(', source)
        self.assertIn('transcriptPane(', source)
        self.assertIn('height: max(', source)
        self.assertNotIn('ViewThatFits(in: .vertical)', source)
        self.assertIn('accessibilityIdentifier("files-page-scroll")', source)
        self.assertIn('      footer\n', source)

    def test_long_explanations_wrap_instead_of_clipping(self):
        source = (ROOT / 'Sources/DictLocalAI/Features/Files/FileTranscriptionView.swift').read_text()
        self.assertGreaterEqual(source.count('.fixedSize(horizontal: false, vertical: true)'), 5)
        self.assertIn('VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs)', source)

    def test_other_sections_remain_scrollable(self):
        meeting = (ROOT / 'Sources/DictLocalAI/Features/Meetings/MeetingView.swift').read_text()
        workspace = workspace_source()
        self.assertIn('ScrollView {', meeting)
        self.assertGreaterEqual(workspace.count('ScrollView {'), 1)
        self.assertIn('HSplitView {', workspace)
        self.assertIn('selection: Binding<UUID?>', workspace)
        transcript = (ROOT / 'Sources/DictLocalAI/Shared/Components/TranscriptResultView.swift').read_text()
        self.assertIn('ScrollView(.vertical)', transcript)
        self.assertIn('LazyVStack(', transcript)
        self.assertIn('.scrollIndicators(.visible)', transcript)


if __name__ == '__main__':
    unittest.main()
