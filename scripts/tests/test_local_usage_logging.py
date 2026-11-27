from workspace_sources import workspace_source
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'Sources' / 'DictLocalAI'


class LocalUsageLoggingContract(unittest.TestCase):
    def test_same_existing_session_log(self):
        reporter = (APP / 'Platform/Diagnostics/UsageTelemetry.swift').read_text()
        base = (APP / 'Platform/Diagnostics/DiagnosticLog.swift').read_text()
        self.assertIn('DiagnosticLog.shared.event(', reporter)
        self.assertIn('"usage", "navigation"', reporter)
        self.assertIn('"usage", "action"', reporter)
        self.assertIn('"usage", "lifecycle"', reporter)
        self.assertIn('DiagnosticLogDirectory.activeDirectory(', base)
        self.assertIn('session-', base)

    def test_navigation_entry_points_have_sources(self):
        app = (APP / 'App/App.swift').read_text()
        service = (APP / 'App/AppServices.swift').read_text()
        ui = workspace_source()
        for source in ('.tray', '.keyboard', '.dock', '.launch', '.internalAction'):
            self.assertIn('source: ' + source, app)
        self.assertIn('source: .sidebar', ui)
        self.assertIn('UsageTelemetry.navigate', service)

    def test_interactions_without_user_contents(self):
        usage = (APP / 'Platform/Diagnostics/UsageTelemetry.swift').read_text()
        for token in ('fileName', 'lastPathComponent', 'microphoneID',
                      'keyboardValue', 'rawText', 'sourceURL'):
            self.assertNotIn(token, usage)
        self.assertIn('approved.contains(choice)', usage)
        prefs = (APP / 'Shared/Preferences/Preferences.swift').read_text()
        self.assertIn('microphone.isEmpty ? "system" : "custom"', prefs)
        self.assertNotIn('choice: microphone)', prefs)

    def test_file_workflow_has_outcome(self):
        file = (APP / 'Features/Files/FileTranscriptionSession.swift').read_text()
        self.assertIn('"outcome=', file)
        self.assertIn('export_success', file)
        self.assertIn('export_failed', file)


if __name__ == '__main__':
    unittest.main()
