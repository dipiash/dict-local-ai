from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[2]


class StyledDMGTests(unittest.TestCase):
    def test_existing_app_icon_and_background_preserved(self):
        script = (ROOT / "scripts/release/make-dmg.sh").read_text()
        layout = (ROOT / "scripts/release/write-dmg-layout.py").read_text()
        self.assertIn('cp Resources/App/AppIcon.icns "$stage/.VolumeIcon.icns"', script)
        self.assertIn('cp Resources/Installer/DMGBackground.png "$stage/.background/background.png"', script)
        self.assertIn('"Dict Local AI.app"', layout)
        self.assertIn('(165, 220)', layout)
        self.assertIn('(580, 220)', layout)
        self.assertNotIn('sips -i', script)
        self.assertTrue((ROOT / "Resources/App/AppIcon.icns").is_file())
        content = (ROOT / "Resources/Installer/DMGBackground.png").read_bytes()
        self.assertEqual(content[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">II", content[16:24]), (760, 440))

    def test_local_and_notarized_builds_use_same_maker(self):
        self.assertIn('bash scripts/release/make-dmg.sh', (ROOT / 'scripts/release/package.sh').read_text())
        self.assertIn('bash scripts/release/make-dmg.sh', (ROOT / 'scripts/release/release-notarized.sh').read_text())


if __name__ == "__main__":
    unittest.main()
