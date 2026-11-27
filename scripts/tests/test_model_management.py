from workspace_sources import workspace_source
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2] / "Sources" / "DictLocalAI"


def source(filename):
    return next(iter(ROOT.rglob(filename))).read_text(encoding="utf-8")


class ModelManagementContractTests(unittest.TestCase):
    def test_only_settings_models_view_offers_download_action(self):
        self.assertIn("installModel(kind)", source("ModelsView.swift"))
        views = workspace_source()
        self.assertRegex(views, r"case \.models:\s+ModelsView\(")
        self.assertIn("installModel: controller.installModel", views)
        self.assertIn("case models", views)
        self.assertIn("static let primary: [WorkspaceSection]", views)
        self.assertIn(".dictation, .files, .meeting, .history, .settings", views)
        for view in ("FileTranscriptionView.swift", "MeetingView.swift"):
            self.assertNotIn("installModel(", source(view))

    def test_hf_only_and_no_hidden_runtime_downloads(self):
        self.assertFalse(list(ROOT.rglob("ModelInstaller.swift")))
        for p in ROOT.rglob("*.swift"):
            self.assertNotIn("models.shelest.app", p.read_text(), p.name)
        services = source("AppServices.swift")
        model_environment = source("HuggingFaceModelEnvironment.swift")
        self.assertIn("ModelHub.offlineMode = offline", model_environment)
        self.assertIn("func restoreModels()", services)
        self.assertIn("func installModel(_ kind: ManagedModel)", services)
        self.assertIn("HuggingFaceModels.download(", model_environment)
        self.assertNotIn("HuggingFaceModels.download(", services)
        self.assertNotIn("WhisperKit", services)
        self.assertIn("controller.restoreModels()", source("App.swift"))
        for name in ("FileTranscriptionSession.swift", "MeetingSession.swift"):
            self.assertNotIn("loadFromHuggingFace", source(name))
            self.assertNotIn("WhisperKit.download", source(name))

    def test_parakeet_publishes_receipt_after_warmup_before_model_swap(self):
        recognition = source("ParakeetModel.swift")
        decoder, service = recognition.split("final class RecognitionService", 1)
        self.assertNotIn("try publish()", decoder)
        load = service.split("func load(_ directory:", 1)[1].split("func loadSpeakerModels", 1)[0]
        self.assertLess(load.index("try model.decode("), load.index("try publish()"))
        self.assertLess(load.index("try publish()"), load.index("self.model = model"))

    def test_pinned_hf_receipts_and_progress(self):
        h = source("HuggingFaceModels.swift")
        self.assertIn("FluidInference/parakeet-ultra-coreml", h)
        self.assertIn("FluidInference/nemotron-3-diarization-coreml", h)
        self.assertNotIn("argmaxinc/whisperkit-coreml", h)
        self.assertIn("ModelRegistry.revisionOverrides", h)
        self.assertIn("SHA256()", h)
        self.assertIn("verifiedDirectory", h)
        self.assertIn("ProgressView(value: value)", source("ModelsView.swift"))
        self.assertIn("fractionCompleted", h)

    def test_only_parakeet_asr_and_speaker_review(self):
        f = source("FileTranscriptionSession.swift")
        view = source("FileTranscriptionView.swift")
        rec = source("ParakeetModel.swift")
        self.assertNotIn("Whisper", rec)
        self.assertNotIn("Whisper", view)
        self.assertNotIn("whisper", source("AppServices.swift").lower())
        self.assertNotIn("whisper", source("ModelsView.swift").lower())
        self.assertNotIn("asrEngine", f)
        self.assertIn("DiarizationReviewConsensus.group", rec)
        self.assertIn("DiarizationSplitReview.find", rec)
        self.assertIn("func assignSpeaker(", f)
        self.assertIn("func addSpeaker(", f)
        for p in ROOT.rglob("*.swift"):
            self.assertNotIn("WhisperKit", p.read_text(), p.name)

    def test_native_sidebar_replaces_legacy_custom_rail(self):
        views = workspace_source()
        self.assertIn('NavigationSplitView(columnVisibility: $columnVisibility)', views)
        self.assertIn('.listStyle(.sidebar)', views)
        self.assertIn('.navigationSplitViewColumnWidth(', views)
        self.assertIn('Binding<WorkspaceSection?>(', views)
        self.assertNotIn('AppStorage("sidebarExpanded")', views)
        self.assertNotIn('private var sidebar: some View', views)
        self.assertIn('groupBoxStyle(AppPanelGroupBoxStyle())', views)


if __name__ == "__main__":
    unittest.main()
