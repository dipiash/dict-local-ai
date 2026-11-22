import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[1] / "evaluation" / 'check-diarization-conflicts.py'
spec = importlib.util.spec_from_file_location('conflict_check', MODULE)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ConflictTests(unittest.TestCase):
    def test_speaker_split_is_flagged_without_false_brief_tail(self):
        audit = {'rawTurns': [{'start': 0, 'end': 60, 'id': 'S2'}],
                 'chunkRuns': [{'start': 0, 'end': 60, 'turns': [
                     {'start': 0, 'end': 10, 'id': 'A'},
                     {'start': 10, 'end': 14, 'id': 'B'},
                     {'start': 15, 'end': 20, 'id': 'B'},
                     {'start': 20, 'end': 57, 'id': 'A'},
                     {'start': 57, 'end': 58, 'id': 'B'},
                 ]}]}
        result = checker.find_conflicts(audit)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['start'], 10)
        self.assertEqual(result[0]['end'], 20)

    def test_independent_labels_are_not_assumed_global(self):
        audit = {'rawTurns': [{'start': 0, 'end': 10, 'id': 'S1'},
                              {'start': 10, 'end': 20, 'id': 'S2'}],
                 'chunkRuns': [{'start': 0, 'end': 20, 'turns': [
                     {'start': 0, 'end': 10, 'id': 'B'},
                     {'start': 10, 'end': 20, 'id': 'A'}]}]}
        self.assertEqual(checker.find_conflicts(audit), [])


if __name__ == '__main__':
    unittest.main()
