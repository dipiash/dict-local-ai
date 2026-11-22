from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "Sources"
MAC = SOURCES / "DictLocalAI"


def swift_sources(directory):
    for path in directory.rglob("*.swift"):
        yield path, path.read_text(encoding="utf-8")


class ArchitectureContracts(unittest.TestCase):
    def test_swiftpm_domain_application_and_storage_dependencies(self):
        manifest = (ROOT / "Package.swift").read_text()
        self.assertIn('.target(name: "DictCore")', manifest)
        self.assertIn('.target(name: "DictApplication", dependencies: ["DictCore"])', manifest)
        self.assertRegex(
            manifest,
            r'name: "DictStorage", dependencies: \["CSQLite", "DictCore", "DictApplication"\]',
        )
        allowed = {
            "DictCore": {"Foundation", "Synchronization"},
            "DictApplication": {"DictCore", "Foundation", "Synchronization"},
            "DictStorage": {"CSQLite", "DictCore", "DictApplication", "Foundation"},
        }
        for target, modules in allowed.items():
            for path, source in swift_sources(SOURCES / target):
                imports = set(re.findall(r"(?m)^\s*import\s+(\w+)", source))
                self.assertLessEqual(imports, modules, str(path))

    def test_application_workflows_depend_on_ports_and_domain_only(self):
        application = SOURCES / "DictApplication"
        workflows = {
            "DictationWorkflow", "DictationCompletion", "FileTranscriptionWorkflow",
            "MeetingWorkflow", "ModelSetup", "RecordingHistory",
        }
        for path, source in swift_sources(application):
            other_workflows = workflows - {path.stem}
            if path.stem == "DictationWorkflow":
                # The completion value carries the finished transcript and delivery policy.
                other_workflows.remove("DictationCompletion")
            for name in other_workflows:
                self.assertNotRegex(source, rf"\b{name}\b", str(path))

    def test_features_resolve_effects_through_application_ports(self):
        concrete = (
            "RecordingDatabase", "RecordingStore", "MeetingJournal", "RecognitionService",
            "MeetingRecognitionPipeline", "HuggingFaceModels", "UserDefaults",
        )
        for path, source in swift_sources(MAC / "Features"):
            for name in concrete:
                self.assertNotRegex(source, rf"\b{name}\b", str(path))

    def test_outbound_adapters_do_not_depend_on_scene_controllers(self):
        for path, source in swift_sources(MAC / "Platform"):
            self.assertNotRegex(
                source,
                r"\b(?:AppServices|AppDelegate|DictationSession|FileTranscriptionSession|"
                r"MeetingSession|HistoryStore|WorkspaceView|Preferences)\b",
                str(path),
            )

    def test_composition_does_not_delegate_writes_to_history_ui(self):
        source = (MAC / "App" / "AppServices.swift").read_text()
        self.assertNotRegex(source, r"\bhistory\.(?:append|appendFile|prune|saveDraft)\b(?!\()")
        self.assertIn("writer: { try RecordingDatabase.require() }", source)
