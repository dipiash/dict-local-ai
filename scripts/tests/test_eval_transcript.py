import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "evaluation" / "eval-transcript.py"
spec = importlib.util.spec_from_file_location("wer_eval", MODULE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class TestWER(unittest.TestCase):
    def test_one_of_each_error(self):
        ref = mod.normalize("a b c d e f g")
        hyp = mod.normalize("a x c e f y g")
        self.assertEqual(mod.count_errors(ref, hyp), (1, 1, 1))

    def test_timecodes_and_speaker_labels_are_removed(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "meeting.txt"
            p.write_text("Источник: Встреча\n\n[00:00:00–00:00:08] Спикер 1: Раз два.\n\n[00:00:08.0–00:00:12.0] Спикер не определён: три.\n", encoding="utf-8")
            self.assertEqual(mod.normalize(mod.get_text(p, True)), ["раз", "два", "три"])

    def test_english_and_russian_channels_and_speakers_are_removed(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "meeting.txt"
            examples = (
                "[00:00:00–00:00:03] [System Audio] Speaker 1: Hello.",
                "[00:00:03–00:00:05] [Microphone] Unknown Speaker: Again.",
                "[00:00:05–00:00:08] [Звук компьютера] Созвон · Спикер 3: Привет.",
            )
            path.write_text("\n".join(examples), encoding="utf-8")
            self.assertEqual(mod.normalize(mod.get_text(path, True)), ["hello", "again", "привет"])

    def test_cyrillic_unicode(self):
        self.assertEqual(mod.normalize("Привет, МИР!"), ["привет", "мир"])
        self.assertEqual(mod.count_errors(["а", "б"], ["а", "б"]), (0, 0, 0))

if __name__ == "__main__":
    unittest.main()
