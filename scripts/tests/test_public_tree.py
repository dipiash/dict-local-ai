import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'development' / 'check-public-tree.py'

@unittest.skipUnless(shutil.which('git'), 'Git is required to validate the index')
class PublicTreeTests(unittest.TestCase):
    def run_gate(self, names):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            script = root / 'scripts' / 'development' / SCRIPT.name
            script.parent.mkdir(parents=True)
            shutil.copyfile(SCRIPT, script)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            for name in names:
                file = root / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('synthetic data', encoding='utf-8')
            subprocess.run(['git', '-C', str(root), 'add', '-f', '.'], check=True)
            return subprocess.run([sys.executable, str(script)], capture_output=True, text=True)

    def test_allows_source_notices_and_benchmark_template(self):
        result = self.run_gate(['LICENSE', 'Sources/Example.swift', 'benchmarks/references.json'])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_tracked_artifacts_and_data(self):
        names = ['.private/notes.txt', 'scripts/__pycache__/cache.pyc',
                 'benchmarks/local/cases.json', 'Documents/voice.m4a', 'keys/distribution.p12',
                 'data/history.sqlite3', 'Models/Encoder.mlmodelc/coremldata.bin']
        result = self.run_gate(names)
        self.assertNotEqual(result.returncode, 0)
        for name in names:
            self.assertIn(name, result.stderr)

    def test_rejects_credentials_even_when_staged_forcibly(self):
        result = self.run_gate(['.env.local', 'dist/release.dmg'])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('.env.local', result.stderr)
        self.assertIn('dist/release.dmg', result.stderr)

    def test_rejects_private_review_names_and_case_variants(self):
        names = ['Fixtures/session.txt', 'INTERNAL-REVIEW-HANDOFF.md',
                 'Dict-Local-AI-CHANGE-MANIFEST(1).tsv',
                 'Dict-Local-AI-INDEPENDENT-REVIEW-2026-11-21.md', 'Transcripts/notes.txt', '.ENV.Local']
        result = self.run_gate(names)
        self.assertNotEqual(result.returncode, 0)
        for name in names:
            self.assertIn(name, result.stderr)
