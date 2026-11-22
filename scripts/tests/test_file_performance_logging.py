from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
FILE = ROOT / "Sources" / "DictLocalAI" / "Platform" / "Speech" / "ParakeetModel.swift"


class FilePerformanceLogContracts(unittest.TestCase):
    def test_replay_completion_uses_variables_inside_window_loop(self):
        source = FILE.read_text(encoding="utf-8")
        loop = source.index("for length in [180, 600] where")
        opening_brace = source.index("{", loop)
        event = source.index('"file_replay_complete"', opening_brace)
        declaration = source.index("let replayStarted =", opening_brace)
        self.assertLess(declaration, event)

        depth = 0
        for char in source[opening_brace:event]:
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
        self.assertGreater(depth, 0, "file_replay_complete escaped its window loop")
        self.assertEqual(source.count('"file_replay_complete"'), 1)
        self.assertIn('window_seconds=\\(length)', source[event: event + 160])
        self.assertIn('systemUptime - replayStarted', source[event: event + 180])


if __name__ == "__main__":
    unittest.main()
