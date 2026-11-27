import AppKit
import Combine
import DictCore
import SwiftUI

final class FloatingPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    let target =
      NSScreen.screens.max {
        $0.visibleFrame.intersection(frameRect).size.area
          < $1.visibleFrame.intersection(frameRect).size.area
      } ?? screen
    let fitted =
      target.map { PanelPlacement.fitted(frameRect, within: $0.visibleFrame) } ?? frameRect
    super.setFrame(fitted, display: flag)
  }
}

extension CGSize {
  fileprivate var area: CGFloat { max(0, width) * max(0, height) }
}

private final class PanelHostingView<Content: View>: NSHostingView<Content> {
  override var mouseDownCanMoveWindow: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
  let controller = AppServices()
  private var status: NSStatusItem!
  private var panel: FloatingPanel!
  private var workspaceWindow: NSWindow?
  private var quitConfirmation: NSAlert?
  private var quitConfirmationPending = false
  private var historyCloseConfirmation: NSAlert?
  private var subscriptions = Set<AnyCancellable>()
  private var permissionRefreshTimer: Timer?
  private var historyRefreshTimer: Timer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.mainMenu = ApplicationMenus.make()
    Task { @MainActor in
      // A permission dialog can start a second app before the first one quits.
      for _ in 0..<50 {
        guard let existing = otherInstance() else {
          finishLaunching()
          return
        }
        if existing.isTerminated { continue }
        try? await Task.sleep(for: .milliseconds(100))
      }
      otherInstance()?.activate(options: [])
      NSApp.terminate(nil)
    }
  }

  private func otherInstance() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(
      withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.dictlocalai.desktop"
    ).first {
      $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
    }
  }

  private func finishLaunching() {
    DiagnosticLog.shared.event(
      "app", "launch",
      "pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(Bundle.main.bundlePath)")
    DiagnosticLog.shared.startWatchdog()
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    status.button?.image = NSImage(
      systemSymbolName: "waveform", accessibilityDescription: "Dict Local AI")
    let menu = NSMenu()
    menu.delegate = self
    status.menu = menu
    panel = FloatingPanel(
      contentRect: NSRect(x: 0, y: 0, width: 536, height: 290),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.isMovableByWindowBackground = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = PanelHostingView(rootView: RecordingView(controller: controller.dictation))
    controller.dictation.objectWillChange.sink { [weak self] _ in
      DispatchQueue.main.async { self?.fitPanelToContent() }
    }.store(in: &subscriptions)
    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
      .sink { [weak self] _ in self?.fitPanelToContent() }
      .store(in: &subscriptions)
    controller.dictation.onShowPanel = { [weak self] in self?.showPanel() }
    controller.dictation.onHidePanel = { [weak self] in
      guard let self, self.controller.meeting.state == .idle else { return }
      self.panel.orderOut(nil)
    }
    controller.dictation.onShowActionResult = { [weak self] in
      self?.showWorkspace(.dictation, source: .internalAction)
    }
    controller.dictation.onOpenSettings = { [weak self] in
      self?.showWorkspace(.settings, source: .internalAction)
    }
    controller.preferences.$enabled.sink { [weak self] enabled in
      self?.status?.button?.image = NSImage(
        systemSymbolName: enabled ? "waveform" : "mic.slash",
        accessibilityDescription: enabled
          ? L10n.text("menu.dictation-enabled") : L10n.text("menu.dictation-disabled"))
    }.store(in: &subscriptions)
    controller.dictation.$phase.sink { [weak self] phase in
      self?.status?.button?.contentTintColor = phase == .recording ? .systemRed : nil
    }.store(in: &subscriptions)
    showWorkspace(.settings, source: .launch)
    controller.meeting.$state.dropFirst().sink { [weak self] state in
      guard let self else { return }
      if state == .recording {
        self.panel.contentView = PanelHostingView(
          rootView: MeetingRecordingView(
            controller: self.controller.meeting, dictation: self.controller.dictation))
        self.status.button?.contentTintColor = .systemRed
        self.showPanel()
      } else if state == .idle {
        self.panel.orderOut(nil)
        self.status.button?.contentTintColor = nil
        self.panel.contentView = PanelHostingView(
          rootView: RecordingView(controller: self.controller.dictation))
      }
    }.store(in: &subscriptions)
    controller.refreshPermissions()
    permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        DiagnosticLog.shared.mainHeartbeat()
        self.controller.refreshPermissions()
      }
    }
    historyRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.controller.history.prune() }
    }
    controller.restoreModels()
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showWorkspace(source: .dock)
    return true
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitConfirmationPending { return .terminateLater }
    let policy = QuitConfirmationPolicy(
      fileRunning: controller.files.running,
      fileUnsaved: controller.files.unsaved,
      meetingRunning: controller.meeting.running,
      meetingUnsaved: controller.meeting.unsaved,
      dictationBusy: controller.dictation.phase == .recording
        || controller.dictation.phase == .processing)
    guard let section = controller.history.draftDirty ? .history : policy.preferredSection else {
      DiagnosticLog.shared.event("app", "quit_without_confirmation")
      return .terminateNow
    }

    // Wait for the menu to close before showing the quit sheet.
    quitConfirmationPending = true
    DiagnosticLog.shared.event(
      "app", "quit_confirmation_required", "section=\(section.rawValue)")
    DispatchQueue.main.async { [weak self, weak sender] in
      guard let self else {
        sender?.reply(toApplicationShouldTerminate: false)
        return
      }
      self.presentQuitConfirmation(section: section, application: sender)
    }
    return .terminateLater
  }

  private func presentQuitConfirmation(
    section: WorkspaceSection, application: NSApplication?
  ) {
    showWorkspace(section, source: .system)
    guard let window = workspaceWindow else {
      DiagnosticLog.shared.event("app", "quit_confirmation_failed", "reason=no_window")
      quitConfirmationPending = false
      application?.reply(toApplicationShouldTerminate: false)
      return
    }
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.text("menu.quit-dict-local-ai")
    alert.informativeText = L10n.text("menu.quit-detail")
    alert.addButton(withTitle: L10n.text("menu.go-back"))
    if controller.history.draftDirty {
      alert.informativeText += L10n.text("menu.nhistory-also-has-unsaved-changes")
      alert.addButton(withTitle: L10n.text("menu.save-changes-and-quit"))
    }
    alert.addButton(withTitle: L10n.text("menu.quit-without-saving"))
    quitConfirmation = alert
    DiagnosticLog.shared.event("app", "quit_confirmation_presented", "section=\(section.rawValue)")
    alert.beginSheetModal(for: window) { [weak self, weak application] response in
      guard let self else {
        application?.reply(toApplicationShouldTerminate: false)
        return
      }
      self.quitConfirmation = nil
      self.quitConfirmationPending = false
      let hadDirtyHistory = self.controller.history.draftDirty
      var confirmed = false
      if hadDirtyHistory && response == .alertSecondButtonReturn {
        confirmed = self.controller.history.saveDraft()
      } else if response == (hadDirtyHistory ? .alertThirdButtonReturn : .alertSecondButtonReturn) {
        self.controller.history.discardDraft()
        confirmed = true
      }
      DiagnosticLog.shared.event(
        "app", confirmed ? "quit_confirmation_accepted" : "quit_confirmation_cancelled")
      application?.reply(toApplicationShouldTerminate: confirmed)
    }
  }
  func applicationWillTerminate(_ notification: Notification) {
    permissionRefreshTimer?.invalidate()
    historyRefreshTimer?.invalidate()
    DiagnosticLog.shared.event("app", "terminate")
    controller.shutdown()
  }
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let enabled = NSMenuItem(
      title: L10n.text("menu.dictation-enabled"), action: #selector(toggleEnabled),
      keyEquivalent: "")
    enabled.state = controller.preferences.enabled ? .on : .off
    enabled.target = self
    menu.addItem(enabled)
    menu.addItem(.separator())
    add(menu, L10n.text("menu.dictation"), #selector(trayShowDictation))
    add(menu, L10n.text("menu.files"), #selector(trayShowFiles))
    add(menu, L10n.text("menu.meetings"), #selector(trayShowMeeting))
    add(menu, L10n.text("menu.history"), #selector(trayShowHistory))
    add(menu, L10n.text("menu.settings"), #selector(trayShowSettings))
    add(menu, L10n.text("menu.about"), #selector(trayShowAbout))
    menu.addItem(.separator())
    add(menu, L10n.text("menu.hands-free-recording"), #selector(startRecording))
    if controller.dictation.canShowLastResult {
      add(menu, L10n.text("menu.last-dictation-result"), #selector(showLastDictationResult))
    }
    menu.addItem(.separator())
    add(menu, L10n.text("menu.quit"), #selector(quit))
  }
  private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)
  }
  @objc private func toggleEnabled() { controller.preferences.enabled.toggle() }
  @objc private func startRecording() {
    UsageTelemetry.action(.tray, .startHandsFree)
    controller.dictation.toggle()
  }
  @objc private func showLastDictationResult() {
    UsageTelemetry.action(.tray, .openLastDictation)
    controller.dictation.reopenLatestResult()
  }
  @objc private func quit() {
    UsageTelemetry.action(.tray, .quit)
    NSApp.terminate(nil)
  }
  @objc private func trayShowSettings() { showWorkspace(.settings, source: .tray) }
  @objc private func trayShowDictation() { showWorkspace(.dictation, source: .tray) }
  @objc private func trayShowFiles() { showWorkspace(.files, source: .tray) }
  @objc private func trayShowMeeting() { showWorkspace(.meeting, source: .tray) }
  @objc private func trayShowHistory() { showWorkspace(.history, source: .tray) }
  @objc private func trayShowAbout() { showWorkspace(.about, source: .tray) }
  @objc func toggleNativeSidebar() {
    showWorkspace(source: .system)
    controller.requestSidebarToggle()
  }
  @objc func showSettings() { showWorkspace(.settings, source: .keyboard) }
  @objc func showDictation() { showWorkspace(.dictation, source: .keyboard) }
  @objc func showFiles() { showWorkspace(.files, source: .keyboard) }
  @objc func showMeeting() { showWorkspace(.meeting, source: .keyboard) }
  @objc func showHistory() { showWorkspace(.history, source: .keyboard) }
  @objc func showAbout() { showWorkspace(.about, source: .keyboard) }

  private func showWorkspace(
    _ section: WorkspaceSection? = nil, source: UsageTelemetry.Source = .internalAction
  ) {
    if let section {
      controller.openWorkspace(section, source: source)
    } else {
      controller.reopenWorkspace(source: source)
    }
    UsageTelemetry.lifecycle(.workspaceOpen, section: controller.router.selected)
    DiagnosticLog.shared.event(
      "navigation", "workspace_open", "section=\(controller.router.selected.rawValue)")
    if workspaceWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false)
      window.title = "Dict Local AI"
      // A direct hosting view can resize the window or render blank.
      let hostContainer = NSView(
        frame: window.contentView?.bounds
          ?? NSRect(
            x: 0, y: 0, width: 940, height: 660))
      let hostingView = NSHostingView(
        rootView: WorkspaceView(controller: controller, preferences: controller.preferences)
          .font(AppStyle.body).controlSize(.regular))
      hostingView.sizingOptions = []
      hostingView.frame = hostContainer.bounds
      hostingView.translatesAutoresizingMaskIntoConstraints = false
      hostContainer.addSubview(hostingView)
      NSLayoutConstraint.activate([
        hostingView.leadingAnchor.constraint(equalTo: hostContainer.leadingAnchor),
        hostingView.trailingAnchor.constraint(equalTo: hostContainer.trailingAnchor),
        hostingView.topAnchor.constraint(equalTo: hostContainer.topAnchor),
        hostingView.bottomAnchor.constraint(equalTo: hostContainer.bottomAnchor),
      ])
      window.contentView = hostContainer
      window.contentMinSize = NSSize(
        width: DesignTokens.Layout.screenMinimumWidth,
        height: DesignTokens.Layout.screenMinimumHeight)
      window.isReleasedWhenClosed = false
      window.delegate = self
      DiagnosticLog.shared.event(
        "window", "workspace_size_policy",
        "source=appkit min_width=\(Int(window.contentMinSize.width)) min_height=\(Int(window.contentMinSize.height))"
      )
      window.center()
      workspaceWindow = window
    }
    if workspaceWindow?.isMiniaturized == true {
      workspaceWindow?.deminiaturize(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
    workspaceWindow?.makeKeyAndOrderFront(nil)
    if let window = workspaceWindow, let container = window.contentView,
      let hosting = container.subviews.first
    {
      container.layoutSubtreeIfNeeded()
      let size = hosting.bounds.size
      DiagnosticLog.shared.event(
        "window",
        size.width > 1 && size.height > 1 ? "workspace_host_ready" : "workspace_host_zero_bounds",
        "width=\(Int(size.width)) height=\(Int(size.height)) section=\(controller.router.selected.rawValue)"
      )
    }
    controller.refreshPermissions()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard sender === workspaceWindow, controller.history.draftDirty else { return true }
    guard historyCloseConfirmation == nil else { return false }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.text("menu.save-changes-to-history")
    alert.informativeText = L10n.text("menu.unsaved-transcript-edits-will-be")
    alert.addButton(withTitle: L10n.text("menu.save"))
    alert.addButton(withTitle: L10n.text("menu.close-without-saving"))
    alert.addButton(withTitle: L10n.text("menu.cancel"))
    historyCloseConfirmation = alert
    NSApp.activate(ignoringOtherApps: true)
    sender.makeKeyAndOrderFront(nil)
    DiagnosticLog.shared.event("history-ui", "window_close_blocked_unsaved")
    alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
      guard let self else { return }
      self.historyCloseConfirmation = nil
      guard let sender else { return }
      if response == .alertFirstButtonReturn {
        if self.controller.history.saveDraft() { sender.performClose(nil) }
      } else if response == .alertSecondButtonReturn {
        self.controller.history.discardDraft()
        sender.performClose(nil)
      }
    }
    return false
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow,
      window === workspaceWindow
    else { return }
    controller.closeWorkspace()
    DiagnosticLog.shared.event("navigation", "workspace_closed")
    UsageTelemetry.lifecycle(.workspaceClose, section: controller.router.selected)
  }

  func windowDidResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === workspaceWindow,
      !window.inLiveResize
    else { return }
    DiagnosticLog.shared.event(
      "window", "workspace_resize_outside_drag",
      "width=\(Int(window.contentLayoutRect.width)) height=\(Int(window.contentLayoutRect.height)) section=\(controller.router.selected.rawValue)"
    )
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === workspaceWindow else { return }
    DiagnosticLog.shared.event(
      "window", "workspace_resize_by_user",
      "width=\(Int(window.contentLayoutRect.width)) height=\(Int(window.contentLayoutRect.height)) section=\(controller.router.selected.rawValue)"
    )
  }

  func windowDidMiniaturize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === workspaceWindow else { return }
    UsageTelemetry.lifecycle(.windowMinimized, section: controller.router.selected)
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === workspaceWindow else { return }
    UsageTelemetry.lifecycle(.windowRestored, section: controller.router.selected)
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    UsageTelemetry.lifecycle(.appActivated, section: controller.router.selected)
  }

  func applicationDidResignActive(_ notification: Notification) {
    UsageTelemetry.lifecycle(.appDeactivated, section: controller.router.selected)
  }

  private func fitPanelToContent() {
    guard let panel, let content = panel.contentView else { return }
    content.layoutSubtreeIfNeeded()
    let size = content.fittingSize
    guard size.width > 0, size.height > 0 else { return }
    panel.setContentSize(size)
    panel.setFrame(panel.frame, display: true)
  }
  private func showPanel() {
    fitPanelToContent()
    let screen = screenForFrontmostWindow() ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen else { return }
    let visible = screen.visibleFrame
    panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 24))
    panel.orderFrontRegardless()
  }
  private func screenForFrontmostWindow() -> NSScreen? {
    guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
      let window = windows.first(where: {
        ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid)
          && ($0[kCGWindowLayer as String] as? Int) == 0
      }),
      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
      let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"],
      let height = bounds["Height"],
      let primary = NSScreen.screens.first
    else { return nil }
    let center = NSPoint(x: x + width / 2, y: primary.frame.maxY - y - height / 2)
    return NSScreen.screens.first { $0.frame.contains(center) }
  }
}

@MainActor
enum ApplicationMenus {
  static func make() -> NSMenu {
    let main = NSMenu()
    let application = NSMenu(title: "Dict Local AI")
    let applicationItem = NSMenuItem()
    applicationItem.submenu = application
    main.addItem(applicationItem)
    application.addItem(
      withTitle: L10n.text("menu.hide-dict-local-ai"), action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h")
    let hideOthers = application.addItem(
      withTitle: L10n.text("menu.hide-others"),
      action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    application.addItem(
      withTitle: L10n.text("menu.show-all"),
      action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: "")
    application.addItem(.separator())
    let settings = application.addItem(
      withTitle: L10n.text("menu.settings"), action: #selector(AppDelegate.showSettings),
      keyEquivalent: ",")
    settings.target = NSApp.delegate as? AppDelegate
    application.addItem(.separator())
    let quit = application.addItem(
      withTitle: L10n.text("menu.quit-dict-local-ai-label"),
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    quit.target = NSApp

    let edit = NSMenu(title: L10n.text("menu.edit"))
    let editItem = NSMenuItem(title: L10n.text("menu.edit"), action: nil, keyEquivalent: "")
    editItem.submenu = edit
    main.addItem(editItem)
    edit.addItem(withTitle: L10n.text("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(
      withTitle: L10n.text("menu.redo"), action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(
      withTitle: L10n.text("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(
      withTitle: L10n.text("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(
      withTitle: L10n.text("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(.separator())
    edit.addItem(
      withTitle: L10n.text("menu.select-all"), action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a")

    let windowMenu = NSMenu(title: L10n.text("menu.window"))
    let windowItem = NSMenuItem(title: L10n.text("menu.window"), action: nil, keyEquivalent: "")
    windowItem.submenu = windowMenu
    main.addItem(windowItem)
    windowMenu.addItem(
      withTitle: L10n.text("menu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m")
    windowMenu.addItem(
      withTitle: L10n.text("menu.close-window"), action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w")
    windowMenu.addItem(.separator())
    let toggleSidebar = windowMenu.addItem(
      withTitle: L10n.text("menu.toggle-sidebar"),
      action: #selector(AppDelegate.toggleNativeSidebar), keyEquivalent: "s")
    toggleSidebar.target = NSApp.delegate as? AppDelegate
    toggleSidebar.keyEquivalentModifierMask = [.command, .control]
    windowMenu.addItem(.separator())
    let navigation: [(String, Selector, String)] = [
      (L10n.text("menu.dictation-label"), #selector(AppDelegate.showDictation), "1"),
      (L10n.text("menu.files-label"), #selector(AppDelegate.showFiles), "2"),
      (L10n.text("menu.meetings-label"), #selector(AppDelegate.showMeeting), "3"),
      (L10n.text("menu.history-label"), #selector(AppDelegate.showHistory), "4"),
      (L10n.text("menu.settings-label"), #selector(AppDelegate.showSettings), "5"),
      (L10n.text("menu.about-label"), #selector(AppDelegate.showAbout), "6"),
    ]
    for (title, action, key) in navigation {
      windowMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        .target = NSApp.delegate as? AppDelegate
    }
    NSApp.windowsMenu = windowMenu
    return main
  }
}

@main enum DictLocalAIApplication {
  @MainActor static func main() {
    if let command = RecognitionArguments.parse(Array(CommandLine.arguments.dropFirst())) {
      RecognitionCommandRunner.start(command)
    }
    if CommandLine.arguments.contains("--check-localization") {
      LocalizationCheck.printResult()
      return
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}
