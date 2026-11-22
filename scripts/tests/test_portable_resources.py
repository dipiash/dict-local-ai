import importlib.util
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "prepare_portable_resources", ROOT / "scripts/build/prepare-portable-resources.py"
)
PREPARER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARER)


class PortableResourceTests(unittest.TestCase):
    def test_accessor_change_invalidates_compiler_overlay_path(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            source = root / "portable-resource-bundle.swift"
            source.write_text("first accessor")
            with mock.patch.object(PREPARER, "__file__", str(root / "prepare.py")):
                original = PREPARER.prepare(root / "build", root / "overlays")
                self.assertEqual(original, PREPARER.prepare(root / "build", root / "overlays"))
                source.write_text("updated accessor")
                self.assertNotEqual(original, PREPARER.prepare(root / "build", root / "overlays"))

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "requires macOS Swift")
    def test_packaged_accessor_loads_resources_without_development_fallback(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp).resolve()
            binary_dir = root / "build with spaces"
            generated = binary_dir / "FluidAudio.build/DerivedSources/resource_bundle_accessor.swift"
            generated.parent.mkdir(parents=True)
            generated.write_text(
                'import Foundation\nextension Bundle { static var module: Bundle { '
                'fatalError("DEVELOPER_FALLBACK") } }\n'
            )
            overlay = PREPARER.prepare(binary_dir, root / "overlays")
            app = root / "Resource Probe.app"
            executable = app / "Contents/MacOS/ResourceProbe"
            executable.parent.mkdir(parents=True)
            resources = app / "Contents/Resources/FluidAudio_FluidAudio.bundle"
            resources.mkdir(parents=True)
            (resources / "fixture.txt").write_text("portable")
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": "ResourceProbe", "CFBundlePackageType": "APPL",
                "CFBundleIdentifier": "local.dict.resource-probe",
            }))
            main = root / "main.swift"
            main.write_text(
                'import Foundation\n'
                'let url = Bundle.module.url(forResource: "fixture", withExtension: "txt")!\n'
                'print(try String(contentsOf: url, encoding: .utf8))\n'
            )
            command = [
                "/usr/bin/arch", "-arm64", "xcrun", "swiftc", "-O", "-gnone", "-swift-version", "6",
                "-target", "arm64-apple-macosx15.0",
                "-module-cache-path", str(root / "module-cache"),
                "-vfsoverlay", str(overlay), str(generated), str(main), "-o", str(executable),
            ]
            subprocess.run(command, check=True, capture_output=True, text=True)
            # The build tree and generated accessor are unavailable at runtime.
            shutil.rmtree(binary_dir)
            result = subprocess.run(
                ["/usr/bin/arch", "-arm64", str(executable)], cwd="/",
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "portable")
            self.assertNotIn(b"DEVELOPER_FALLBACK", executable.read_bytes())
            self.assertNotIn(str(root).encode(), executable.read_bytes())


if __name__ == "__main__":
    unittest.main()
