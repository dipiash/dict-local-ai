import importlib.util
import pathlib
import plistlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "verify_portable_bundle", ROOT / "scripts/build/verify-portable-bundle.py"
)
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class PortableBundleContractTests(unittest.TestCase):
    def test_build_has_no_embedded_checkout_path(self):
        build = (ROOT / "scripts/build/build.sh").read_text()
        logger = (ROOT / "Sources/DictLocalAI/Platform/Diagnostics/DiagnosticLog.swift").read_text()
        self.assertNotIn('PlistBuddy -c "Add :DictProjectRoot', build)
        self.assertNotIn('object(forInfoDictionaryKey: "DictProjectRoot")', logger)
        self.assertNotIn('currentDirectoryPath', logger)
        self.assertIn('verify-portable-bundle.py', build)
        package = (ROOT / 'scripts/release/package.sh').read_text()
        self.assertIn('verify-portable-bundle.py', package)
        self.assertIn('shasum -a 256 Dict-Local-AI.dmg >> SHA256SUMS', package)
        self.assertIn('DiagnosticLogDirectory.activeDirectory(', logger)

    def test_capture_hang_uses_same_runtime_directory(self):
        helper = (ROOT / 'scripts/development/capture-hang.sh').read_text()
        self.assertIn('Library/Logs/Dict Local AI', helper)
        self.assertIn('DICT_LOG_DIR', helper)
        self.assertNotIn('.build/logs', helper)

    def test_verifier_accepts_portable_and_rejects_checkout_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            bundle = pathlib.Path(temp) / "Dict Local AI.app" / "Contents"
            bundle.mkdir(parents=True)
            info = bundle / 'Info.plist'
            good = {"CFBundleIdentifier": "app.dictlocalai.desktop"}
            info.write_bytes(plistlib.dumps(good))
            CHECKER.check(bundle.parent)
            for bad in (
                dict(good, DictProjectRoot='/Users/dev/IdeaProjects/dict-local-ai'),
                dict(good, OtherPath='/Users/dev/test'),
                dict(good, OtherPath='/home/dev/test'),
            ):
                info.write_bytes(plistlib.dumps(bad))
                with self.assertRaises(ValueError):
                    CHECKER.check(bundle.parent)


    def test_embedded_checkout_path_is_rejected_in_bundle_payload(self):
        with tempfile.TemporaryDirectory() as temp:
            base = pathlib.Path(temp)
            checkout = base / "checkout with spaces"
            contents = base / "Dict Local AI.app" / "Contents"
            contents.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(
                plistlib.dumps({"CFBundleIdentifier": "app.dictlocalai.desktop"})
            )
            checkout.mkdir()
            alias = base / "checkout alias"
            alias.symlink_to(checkout, target_is_directory=True)
            for spelling in (checkout, checkout.resolve(), alias, alias.resolve()):
                with self.subTest(spelling=spelling):
                    (contents / "FakeBinary").write_bytes(
                        b"binary prefix\0" + str(spelling).encode() + b"/Sources/A.swift\0"
                    )
                    with self.assertRaisesRegex(ValueError, "FakeBinary"):
                        CHECKER.check(contents.parent, alias if spelling == alias else checkout)

    def test_similar_directory_name_is_not_a_checkout_path(self):
        with tempfile.TemporaryDirectory() as temp:
            base = pathlib.Path(temp)
            checkout = base / "checkout"
            contents = base / "Dict Local AI.app" / "Contents"
            contents.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(
                plistlib.dumps({"CFBundleIdentifier": "app.dictlocalai.desktop"})
            )
            (contents / "FakeBinary").write_bytes(
                str(checkout).encode() + b"-other/Sources/A.swift\0"
            )
            CHECKER.check(contents.parent, checkout)
