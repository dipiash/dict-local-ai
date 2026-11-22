import runpy
import sys
import tempfile
import types
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class LayoutRecordsTests(unittest.TestCase):
    def test_records_finder_background_and_icon_positions(self):
        records = {}

        class FakeStore:
            def __getitem__(self, name):
                return records.setdefault(name, {})

        class FakeDSStore:
            @staticmethod
            @contextmanager
            def open(path, mode):
                self.assertTrue(path.endswith('.DS_Store'))
                self.assertEqual(mode, 'w+')
                yield FakeStore()

        class FakeAlias:
            def __init__(self, **kwargs):
                self.kwargs = kwargs

            def to_bytes(self):
                return b'background-alias'

        ds_store = types.ModuleType('ds_store')
        ds_store.DSStore = FakeDSStore
        mac_alias = types.ModuleType('mac_alias')
        for name in ('ALIAS_EJECTABLE_DISK', 'ALIAS_HFS_VOLUME_SIGNATURE', 'ALIAS_KIND_FILE', 'ALIAS_NO_CNID'):
            setattr(mac_alias, name, 1)
        mac_alias.Alias = FakeAlias
        mac_alias.TargetInfo = lambda **kw: kw
        mac_alias.VolumeInfo = lambda **kw: kw
        with patch.dict(sys.modules, {'ds_store': ds_store, 'mac_alias': mac_alias}):
            module = runpy.run_path(str(ROOT / 'scripts/release/write-dmg-layout.py'))
            with tempfile.TemporaryDirectory() as folder:
                module['write_layout'](Path(folder) / '.DS_Store')
        self.assertEqual(records['.']['icvp']['backgroundType'], 2)
        self.assertEqual(records['.']['icvp']['backgroundImageAlias'], b'background-alias')
        self.assertEqual(records['.']['bwsp']['WindowBounds'], '{{180, 120}, {760, 440}}')
        self.assertEqual(records['Dict Local AI.app']['Iloc'], (165, 220))
        self.assertEqual(records['Applications']['Iloc'], (580, 220))


if __name__ == '__main__':
    unittest.main()
