import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "swift_dependencies", ROOT / "scripts/development/check-swift-dependencies.py"
)
dependencies = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dependencies)


class SwiftDependencyTests(unittest.TestCase):
    def setUp(self):
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.source = Path(temporary.name)

    def write(self, name, contents):
        path = self.source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    def test_reports_cycle_with_source_locations(self):
        self.write("App/Host.swift", "struct Host { let view: FeatureView }")
        self.write("Features/Example/View.swift", "@MainActor\nstruct FeatureView { let host: Host }")
        graph = dependencies.graph_for(self.source)

        self.assertEqual(dependencies.find_cycle(graph), ["App", "Features/Example", "App"])
        self.assertEqual(
            graph["Features/Example"]["App"], (Path("Features/Example/View.swift"), "Host")
        )

    def test_ignores_type_names_in_comments_and_literal_text(self):
        self.write("App/Host.swift", "struct Host { let view: FeatureView }")
        self.write(
            "Features/Example/View.swift",
            'struct FeatureView {\n  // Host\n  let hint = #"Host"#\n  let more = "Host"\n}',
        )

        self.assertIsNone(dependencies.find_cycle(dependencies.graph_for(self.source)))

    def test_finds_indirect_cycle(self):
        self.write("Features/One/One.swift", "struct One { let two: Two }")
        self.write("Features/Two/Two.swift", "struct Two { let three: Three }")
        self.write("Features/Three/Three.swift", "struct Three { let one: One }")

        self.assertEqual(
            dependencies.find_cycle(dependencies.graph_for(self.source)),
            ["Features/One", "Features/Two", "Features/Three", "Features/One"],
        )
