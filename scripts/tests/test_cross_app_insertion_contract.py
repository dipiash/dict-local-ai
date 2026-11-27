from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CrossAppInsertionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.session = (ROOT / "Sources/DictLocalAI/Features/Dictation/DictationSession.swift").read_text()
        cls.insertion = (ROOT / "Sources/DictLocalAI/Platform/Input/TextInsertion.swift").read_text()

    def test_capture_target_when_stopping_not_starting(self):
        start = self.session.split("  func start(handsFree: Bool) {", 1)[1].split("  func toggle() {", 1)[0]
        finish = self.session.split("  func finish() {", 1)[1].split("  private func complete(", 1)[0]
        self.assertNotIn("completionTarget = TextInsertion.target()", start)
        self.assertIn("completionTarget = TextInsertion.target()", finish)

    def test_external_paste_not_gated_on_ax_editable_text_role(self):
        capture = self.insertion.split("  static func target()", 1)[1].split("  static func matches(", 1)[0]
        self.assertNotIn("guard let resolved = resolve", capture)
        self.assertNotIn("eligible(", capture)
        self.assertNotIn("AXUIElementSetAttributeValue", self.insertion)
        self.assertIn("commandDown.type = .flagsChanged", self.insertion)
        self.assertIn("commandDown.flags = .maskCommand", self.insertion)
        self.assertIn("vDown.flags = .maskCommand", self.insertion)
        self.assertIn("commandUp.type = .flagsChanged", self.insertion)
        self.assertIn("commandUp.flags = []", self.insertion)
        self.assertIn("for event in events { event.post(tap: .cghidEventTap) }", self.insertion)

    def test_no_blind_double_delivery(self):
        self.assertIn("private static func postShortUnicode", self.insertion)
        self.assertIn("guard postShortUnicode(text, target: target) else { return .unavailable }", self.insertion)
        self.assertIn("paste_posted_unconfirmed", self.insertion)
        self.assertNotIn(".postToPid", self.insertion)

    def test_maintain_clipboard_and_local_editor_paths(self):
        self.assertIn("NSPasteboard.general.setString", self.insertion)
        self.assertIn("editor.insertText(text, replacementRange: editor.selectedRange())", self.insertion)
        self.assertIn('"fallback_clipboard"', self.session)


if __name__ == "__main__":
    unittest.main()
