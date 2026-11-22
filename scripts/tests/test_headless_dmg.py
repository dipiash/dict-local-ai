from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class HeadlessDMGTests(unittest.TestCase):
    def test_image_generated_from_prepared_folder(self):
        script = (ROOT / "scripts/release/make-dmg.sh").read_text()
        self.assertIn("hdiutil create", script)
        self.assertIn('-srcfolder "$stage"', script)
        self.assertIn('scripts/release/write-dmg-layout.py', script)
        self.assertIn('ln -s /Applications', script)
        self.assertNotIn("\ncreate-dmg ", script)
        self.assertNotIn("\n  -m dmgbuild", script)
        self.assertNotIn("\n/usr/bin/hdiutil attach", script)
        self.assertNotIn("\nopen ", script)
        self.assertNotIn("osascript", script)

    def test_app_signature_and_old_dmg_are_preserved_on_failure(self):
        script = (ROOT / "scripts/release/make-dmg.sh").read_text()
        self.assertIn('/usr/bin/ditto "$app" "$stage/Dict Local AI.app"', script)
        self.assertIn('temporary_output=', script)
        self.assertIn('mv -f "$temporary_output" "$output"', script)
        self.assertIn('trap ', script)


if __name__ == "__main__":
    unittest.main()
