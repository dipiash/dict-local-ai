from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = (ROOT / 'Sources/DictLocalAI/App/App.swift').read_text()

class QuitConfirmationContractTests(unittest.TestCase):
    def test_uses_nonblocking_window_sheet_not_background_modal(self):
        self.assertIn('return .terminateLater', APP)
        self.assertIn('DispatchQueue.main.async', APP)
        self.assertIn('showWorkspace(section, source: .system)', APP)
        self.assertIn('window.makeKeyAndOrderFront(nil)', APP)
        self.assertIn('alert.beginSheetModal(for: window)', APP)
        self.assertNotIn('alert.runModal()', APP)
        self.assertIn('reply(toApplicationShouldTerminate: confirmed)', APP)

    def test_logs_all_quit_outcomes(self):
        for event in ('quit_confirmation_required', 'quit_confirmation_presented',
                      'quit_confirmation_accepted', 'quit_confirmation_cancelled',
                      'quit_without_confirmation'):
            self.assertIn(event, APP)
        self.assertIn('quitConfirmationPending', APP)

if __name__ == '__main__':
    unittest.main()
