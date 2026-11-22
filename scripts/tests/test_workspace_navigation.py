from workspace_sources import workspace_source
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / "Sources" / "DictLocalAI"
CORE = ROOT / "Sources" / "DictCore"


class AppRouterContractTests(unittest.TestCase):
    def test_only_one_workspace_window_and_no_modal_page_windows(self):
        app = (APP / "App/App.swift").read_text()
        self.assertEqual(app.count("let window = NSWindow("), 1)
        self.assertIn("rootView: WorkspaceView(", app)
        self.assertNotIn("filesWindow", app)
        self.assertNotIn("meetingWindow", app)
        self.assertNotIn("dictationResultWindow", app)
        self.assertNotIn("settingsOpenCount", app)
        self.assertIn("controller.closeWorkspace()", app)

    def test_tray_sections_route_to_main_workspace(self):
        app = (APP / "App/App.swift").read_text()
        for section in ("settings", "dictation", "files", "meeting", "history", "about"):
            name = section[0].upper() + section[1:]
            self.assertIn(f"func show{name}() {{ showWorkspace(.{section}, source: .keyboard) }}", app)
            self.assertIn(f"func trayShow{name}() {{ showWorkspace(.{section}, source: .tray) }}", app)
        self.assertIn("applicationShouldHandleReopen", app)
        self.assertIn("showWorkspace(source: .dock)", app)
        self.assertIn("self?.showWorkspace(.dictation, source: .internalAction)", app)

    def test_sidebar_tracks_shared_navigation_not_a_local_default(self):
        views = workspace_source()
        self.assertIn("switch controller.router.selected", views)
        self.assertIn("controller.openWorkspace(section, source: .sidebar)", views)
        self.assertIn('NavigationSplitView(columnVisibility: $columnVisibility)', views)
        self.assertNotIn("@State private var section", views)
        self.assertNotIn("section = .settings", views)
        self.assertIn("case .dictation:", views)
        self.assertIn("DictationWorkspaceView(controller: controller.dictation, preferences: preferences)", views)
        self.assertIn("HistoryView(store: controller.history", views)
        self.assertIn('case .history: HistoryView(store: controller.history', views)
        self.assertIn("NSApp.keyWindow?.makeFirstResponder(nil)", views)
        navigation = (CORE / "Navigation/AppRouter.swift").read_text()
        self.assertIn("if !isOpen { selected = .settings }", navigation)


    def test_app_router_is_the_only_navigation_state_owner(self):
        router = (CORE / "Navigation/AppRouter.swift").read_text()
        service = (APP / "App/AppServices.swift").read_text()
        views = workspace_source()
        app = (APP / "App/App.swift").read_text()
        self.assertIn("public struct AppRouter: Equatable, Sendable", router)
        self.assertIn("public private(set) var pendingSection: WorkspaceSection?", router)
        self.assertIn("@Published private(set) var router = AppRouter()", service)
        self.assertNotIn("@Published private(set) var workspace", service)
        self.assertNotIn("@Published private(set) var pendingWorkspaceSection", service)
        self.assertIn("router.request(section, historyHasUnsavedEdits: history.draftDirty)", service)
        self.assertIn("router.confirmPending()", service)
        self.assertIn("router.cancelPending()", service)
        self.assertIn("controller.router.pendingSection != nil", views)
        self.assertIn("controller.router.selected", views)
        self.assertIn("controller.router.selected", app)
        self.assertFalse((CORE / "WorkspaceNavigation.swift").exists())

    def test_history_confirmation_uses_existing_save_discard_contract(self):
        service = (APP / "App/AppServices.swift").read_text()
        router = (CORE / "Navigation/AppRouter.swift").read_text()
        self.assertIn("guard history.saveDraft() else { return }", service)
        self.assertIn("history.discardDraft()", service)
        self.assertIn("selected == .history && section != .history", router)
        self.assertIn("return .confirmationRequired", router)
        self.assertIn("if !isOpen { selected = .settings }", router)


if __name__ == "__main__":
    unittest.main()
