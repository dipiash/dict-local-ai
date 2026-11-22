import AppKit
import DictCore
import ServiceManagement
import SwiftUI

extension WorkspaceSection {
  fileprivate static let primary: [WorkspaceSection] = [
    .dictation, .files, .meeting, .history, .settings,
  ]

  fileprivate var title: String {
    switch self {
    case .dictation: L10n.text("menu.dictation-label")
    case .files: L10n.text("menu.files-label")
    case .meeting: L10n.text("menu.meetings-label")
    case .history: L10n.text("menu.history-label")
    case .settings: L10n.text("menu.settings-label")
    case .about: L10n.text("menu.about-label")
    }
  }

  fileprivate var symbol: String {
    switch self {
    case .dictation: "waveform"
    case .files: "doc.text"
    case .meeting: "person.2.wave.2"
    case .settings: "slider.horizontal.3"
    case .history: "clock"
    case .about: "info.circle"
    }
  }
}

struct WorkspaceView: View {
  @ObservedObject var controller: AppServices
  @ObservedObject var preferences: Preferences
  @StateObject private var capture = ShortcutCapture()
  @State private var microphones = AudioCapture.microphones()
  @State private var login = SMAppService.mainApp.status == .enabled
  @State private var error = ""
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var settingsTab = SettingsTab.general

  private enum SettingsTab: String, CaseIterable {
    case general
    case permissions
    case models
    case shortcuts
    case microphone
    case storage
    case startup

    var title: String {
      switch self {
      case .general: L10n.text("settings.general")
      case .permissions: L10n.text("settings.permissions")
      case .models: L10n.text("settings.models")
      case .shortcuts: L10n.text("settings.shortcuts")
      case .microphone: L10n.text("settings.microphone")
      case .storage: L10n.text("settings.storage")
      case .startup: L10n.text("settings.startup")
      }
    }

    var telemetryKey: String {
      switch self {
      case .general: "general"
      case .permissions: "permissions"
      case .models: "models"
      case .shortcuts: "shortcuts"
      case .microphone: "microphone"
      case .storage: "storage"
      case .startup: "startup"
      }
    }

    var symbol: String {
      switch self {
      case .general: "gearshape"
      case .permissions: "hand.raised"
      case .models: "cpu"
      case .shortcuts: "keyboard"
      case .microphone: "mic"
      case .storage: "externaldrive"
      case .startup: "power"
      }
    }
  }

  private var appVersion: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return version.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List(
        selection: Binding<WorkspaceSection?>(
          get: { controller.router.selected },
          set: { section in
            guard let section else { return }
            capture.cancel()
            UsageTelemetry.navigationRequested(to: section, source: .sidebar)
            controller.openWorkspace(section, source: .sidebar)
          })
      ) {
        Section {
          ForEach(WorkspaceSection.primary, id: \.self) { item in
            Label(item.title, systemImage: item.symbol)
              .tag(item)
              .accessibilityIdentifier("workspace-nav-\(item.rawValue)")
          }
        }
        Section {
          Label(WorkspaceSection.about.title, systemImage: WorkspaceSection.about.symbol)
            .tag(WorkspaceSection.about)
        }
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(
        min: DesignTokens.Layout.sidebarMinimumWidth,
        ideal: DesignTokens.Layout.sidebarIdealWidth,
        max: DesignTokens.Layout.sidebarMaximumWidth
      )
      .accessibilityIdentifier("workspace-sidebar")
    } detail: {
      Group {
        switch controller.router.selected {
        case .dictation:
          DictationWorkspaceView(controller: controller.dictation, preferences: preferences)
        case .files: FileTranscriptionView(controller: controller.files, models: controller)
        case .meeting:
          MeetingView(
            controller: controller.meeting, preferences: controller.preferences,
            models: controller)
        case .settings: settings
        case .history: HistoryView(store: controller.history, meeting: controller.meeting)
        case .about: about
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // Nested split views can leave the detail area blank.
    .background(DesignTokens.Colors.window)
    .groupBoxStyle(AppPanelGroupBoxStyle())
    .font(AppStyle.body).controlSize(.regular)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .confirmationDialog(
      L10n.text("settings.save-changes-to-history-before"),
      isPresented: Binding(
        get: { controller.router.pendingSection != nil },
        set: { if !$0 { controller.cancelPendingNavigation() } })
    ) {
      Button(L10n.text("settings.save-and-continue")) {
        controller.resolvePendingNavigation(save: true)
      }
      Button(L10n.text("settings.continue-without-saving"), role: .destructive) {
        controller.resolvePendingNavigation(save: false)
      }
      Button(L10n.text("menu.cancel"), role: .cancel) { controller.cancelPendingNavigation() }
    } message: {
      Text(L10n.text("settings.you-edited-this-transcript-if"))
    }
    .onChange(of: controller.sidebarToggleRequest) { _, _ in
      let next: NavigationSplitViewVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
      if reduceMotion {
        columnVisibility = next
      } else {
        withAnimation(DesignTokens.Motion.sectionChange) { columnVisibility = next }
      }
    }
    .onChange(of: settingsTab) { _, newTab in
      UsageTelemetry.action(
        .settings, .changeSettingsTab,
        choice: newTab.telemetryKey)
    }
    .onChange(of: controller.router.selected) { _, newSection in
      capture.cancel()
      NSApp.keyWindow?.makeFirstResponder(nil)
      if newSection == .settings { settingsTab = .general }
      UsageTelemetry.sectionVisible(newSection)
    }
    .onChange(of: columnVisibility) { _, visibility in
      UsageTelemetry.sidebarVisibility(visibility == .detailOnly ? "hidden" : "visible")
    }
    .onAppear {
      controller.refreshPermissions()
      settingsTab = .general
    }
    .onDisappear { capture.cancel() }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    ) { _ in
      controller.refreshPermissions()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
    ) { _ in capture.cancel() }
    .alert(
      L10n.text("settings.could-not-change-setting"),
      isPresented: Binding(get: { !error.isEmpty }, set: { if !$0 { error = "" } })
    ) {
      Button(L10n.text("settings.ok")) { error = "" }
    } message: {
      Text(error)
    }
  }
  private var brandMark: some View {
    Group {
      if let url = Bundle.main.url(forResource: "BrandMark", withExtension: "png"),
        let image = NSImage(contentsOf: url)
      {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
      } else {
        Image(systemName: "waveform")
          .resizable()
          .scaledToFit()
          .padding(DesignTokens.Spacing.xs)
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
  }

  private var about: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
        VStack(spacing: DesignTokens.Spacing.s) {
          brandMark.frame(
            width: DesignTokens.Layout.aboutBrandMarkSize,
            height: DesignTokens.Layout.aboutBrandMarkSize)
          Text("Dict Local AI").font(.largeTitle.weight(.semibold))
          Text(L10n.text("settings.version", "\(appVersion)")).foregroundStyle(.secondary)
          Text(L10n.text("about.tagline"))
            .font(AppStyle.body).italic().multilineTextAlignment(.center)
          Text(L10n.text("settings.speech-recognition-meetings-and-audio"))
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.m)
        .appPanel()

        GroupBox {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
            aboutFeatureCard(
              symbol: "cpu", title: L10n.text("settings.on-device-recognition"),
              message: L10n.text("settings.processing-runs-on-your-mac"))
            Divider()
            aboutFeatureCard(
              symbol: "lock", title: L10n.text("settings.privacy"),
              message: L10n.text("settings.audio-and-text-stay-on"))
            Divider()
            aboutFeatureCard(
              symbol: "person.2.wave.2", title: L10n.text("menu.meetings-label"),
              message: L10n.text("settings.transcribe-meetings-and-audio-files"))
            Divider()
            aboutFeatureCard(
              symbol: "waveform", title: L10n.text("menu.dictation-label"),
              message: L10n.text("settings.enter-text-in-apps-and"))
            Divider()
            aboutFeatureCard(
              symbol: "clock.arrow.circlepath", title: L10n.text("menu.history-label"),
              message: L10n.text("settings.text-is-stored-locally-for"))
          }
        }
        GroupBox(L10n.text("settings.technology-and-licenses")) {
          VStack(alignment: .leading, spacing: AppStyle.spacing) {
            Text(
              L10n.text("settings.speech-recognition-uses-parakeet-ultra")
            )
            Text(
              L10n.text("settings.speaker-separation-uses-nemotron-3")
            )
            HStack(spacing: DesignTokens.Spacing.m) {
              Link(
                L10n.text("settings.model-and-license"),
                destination: URL(string: "https://huggingface.co/moondream/parakeet-ultra")!)
              Link(
                "FluidAudio",
                destination: URL(string: "https://github.com/FluidInference/FluidAudio")!)
            }
            Text(L10n.text("settings.the-app-source-code-is"))
              .font(AppStyle.caption).foregroundStyle(.secondary)
          }
        }
      }
      .padding(.horizontal, AppStyle.pagePadding)
      .padding(.vertical, DesignTokens.Spacing.s)
    }
  }

  private func aboutFeatureCard(symbol: String, title: String, message: String) -> some View {
    HStack(spacing: DesignTokens.Spacing.s) {
      Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor)
        .frame(
          width: DesignTokens.Layout.featureIconSize, height: DesignTokens.Layout.featureIconSize)
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
        Text(title).font(AppStyle.body)
        Text(message).font(AppStyle.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }.padding(.vertical, DesignTokens.Spacing.xs)
  }

  private var permissionsSettings: some View {
    SettingsFormPage(
      title: L10n.text("settings.permissions"),
      subtitle: L10n.text("settings.check-microphone-and-accessibility-access")
    ) {
      Text(
        L10n.text("settings.microphone-access-records-your-voice")
      )
      .font(AppStyle.caption).foregroundStyle(.secondary)
      SettingsSection(L10n.text("settings.access-status")) {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
          HStack {
            Text(
              controller.microphoneStatus == .authorized
                ? L10n.text("settings.microphone-access-granted")
                : L10n.text("settings.microphone-for-voice-recording"))
            Spacer()
            if controller.microphoneStatus != .authorized {
              Button(
                controller.microphoneStatus == .notDetermined
                  ? L10n.text("settings.allow") : L10n.text("settings.open-settings")
              ) { controller.requestMicrophone() }
            }
          }
          permissionRow(
            granted: controller.accessibilityGranted,
            allowed: L10n.text("settings.accessibility-access-granted"),
            needed: L10n.text("settings.accessibility-for-shortcuts-and-pasting"),
            action: controller.requestAccessibility,
            actionTitle: controller.accessibilityRequested
              ? L10n.text("settings.open-settings") : L10n.text("settings.allow")
          )
          HStack(alignment: .center, spacing: DesignTokens.Spacing.s) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
              Text(L10n.text("settings.system-audio-audio-only-access"))
              Text(
                L10n.text("settings.macos-asks-for-access-the")
              )
              .font(AppStyle.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.text("settings.open-settings")) {
              UsageTelemetry.action(.settings, .openPrivacySettings)
              controller.openSystemAudioPrivacy()
            }
          }
          if controller.accessibilityGranted && !controller.hotkeysReady {
            permissionRow(
              granted: controller.inputMonitoringGranted,
              allowed: L10n.text("settings.input-monitoring-access-granted"),
              needed: L10n.text("settings.input-monitoring-for-shortcuts"),
              action: controller.requestInputMonitoring,
              actionTitle: controller.inputMonitoringRequested
                ? L10n.text("settings.open-settings") : L10n.text("settings.allow")
            )
          }
        }
      }
    }
  }
  private func permissionRow(
    granted: Bool, allowed: String, needed: String, action: @escaping () -> Void,
    actionTitle: String = L10n.text("settings.allow")
  ) -> some View {
    HStack {
      Text(granted ? "✓ " + allowed : needed)
      Spacer()
      if !granted { Button(actionTitle, action: action) }
    }
  }

  private var loginToggle: some View {
    SettingsToggleRow(
      title: L10n.text("settings.open-at-login"),
      isOn: Binding(
        get: { login },
        set: { value in
          do {
            if value {
              try SMAppService.mainApp.register()
            } else {
              try SMAppService.mainApp.unregister()
            }
            login = SMAppService.mainApp.status == .enabled
            UsageTelemetry.action(.settings, .toggleLaunchOnLogin, value: login)
            if value && !login { SMAppService.openSystemSettingsLoginItems() }
          } catch { self.error = L10n.error(error) }
        }))
  }
  private var settings: some View {
    HSplitView {
      List(
        selection: Binding<SettingsTab?>(
          get: { settingsTab },
          set: { next in
            guard let next else { return }
            UsageTelemetry.settingsRequested(next.telemetryKey)
            settingsTab = next
          }
        )
      ) {
        Section(L10n.text("menu.settings-label")) {
          ForEach(SettingsTab.allCases, id: \.self) { tab in
            Label(tab.title, systemImage: tab.symbol)
              .tag(tab)
              .accessibilityIdentifier("settings-nav-\(tab.telemetryKey)")
          }
        }
      }
      .listStyle(.sidebar)
      .frame(width: DesignTokens.Layout.settingsSidebarIdealWidth)

      Group {
        switch settingsTab {
        case .general: generalSettings
        case .permissions: permissionsSettings
        case .models: ModelsView(controller: controller)
        case .shortcuts: shortcutsSettings
        case .microphone: microphoneSettings
        case .storage: storageSettings
        case .startup: startupSettings
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .layoutPriority(1)
      .accessibilityIdentifier("settings-detail")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityIdentifier("settings-navigation")
  }

  private var generalSettings: some View {
    SettingsFormPage(
      title: L10n.text("settings.general"),
      subtitle: L10n.text("settings.set-your-general-preferences")
    ) {
      SettingsSection(L10n.text("menu.dictation-label")) {
        SettingsToggleRow(title: L10n.text("menu.dictation-enabled"), isOn: $preferences.enabled)
        Text(L10n.text("settings.use-the-shortcut-to-insert"))
          .font(AppStyle.caption).foregroundStyle(.secondary)
      }
      SettingsSection(L10n.text("settings.readiness")) {
        HStack {
          Text(
            controller.ready
              ? L10n.text("settings.parakeet-ultra-is-ready")
              : L10n.text("settings.install-parakeet-ultra-to-continue"))
          Spacer()
          Button(L10n.text("settings.open-models")) { settingsTab = .models }
        }
        HStack {
          Text(L10n.text("settings.microphone-and-input-permissions"))
          Spacer()
          Button(L10n.text("settings.check")) { settingsTab = .permissions }
        }
      }
    }
  }

  private var shortcutsSettings: some View {
    SettingsFormPage(
      title: L10n.text("settings.shortcuts"),
      subtitle: L10n.text("settings.choose-recording-shortcuts")
    ) {
      SettingsSection(L10n.text("settings.hold-to-record")) {
        HStack {
          Text(L10n.text("settings.hold-to-record-label"))
          Spacer()
          Button(
            capture.active == "hold"
              ? L10n.text("settings.press-a-key") : preferences.hold.displayLabel
          ) {
            controller.dictation.cancel()
            UsageTelemetry.action(.settings, .captureHoldShortcut)
            capture.begin("hold", hotkeys: controller.hotkeys) { value in
              if value == preferences.toggle {
                error = L10n.text("settings.choose-a-different-shortcut-for")
              } else {
                preferences.hold = value
              }
            }
          }
        }
      }
      SettingsSection(L10n.text("menu.hands-free-recording")) {
        HStack {
          Text(L10n.text("settings.toggle-recording"))
          Spacer()
          Button(
            capture.active == "toggle"
              ? L10n.text("settings.press-a-shortcut") : preferences.toggle.displayLabel
          ) {
            controller.dictation.cancel()
            UsageTelemetry.action(.settings, .captureToggleShortcut)
            capture.begin("toggle", hotkeys: controller.hotkeys) { value in
              if value == preferences.hold {
                error = L10n.text("settings.choose-a-different-shortcut-for")
              } else {
                preferences.toggle = value
              }
            }
          }
        }
        Text(L10n.text("settings.press-fn-twice-to-start"))
          .font(AppStyle.caption).foregroundStyle(.secondary)
        Button(L10n.text("settings.reset-to-left-option-fn")) {
          UsageTelemetry.action(.settings, .restoreShortcuts)
          preferences.hold = .hold
          preferences.toggle = .toggle
        }
      }
    }
  }

  private var microphoneSettings: some View {
    SettingsFormPage(
      title: L10n.text("settings.microphone"),
      subtitle: L10n.text("settings.choose-an-audio-source-for")
    ) {
      SettingsSection(L10n.text("settings.recording-source")) {
        Picker(L10n.text("settings.source"), selection: $preferences.microphone) {
          Text(L10n.text("settings.current-system-microphone")).tag("")
          ForEach(microphones) { microphone in Text(microphone.name).tag(microphone.id) }
        }
        .disabled(controller.dictation.phase == .recording)
        Button(L10n.text("settings.refresh-list")) {
          UsageTelemetry.action(.settings, .refreshMicrophones)
          microphones = AudioCapture.microphones()
        }
      }
    }
  }

  private var storageSettings: some View {
    SettingsFormPage(
      title: L10n.text("settings.storage"), subtitle: L10n.text("settings.choose-whether-to-keep-a")
    ) {
      SettingsSection(L10n.text("menu.history-label")) {
        SettingsToggleRow(
          title: L10n.text("settings.keep-text-for-the-last"), isOn: $preferences.saveHistory)
        Text(L10n.text("settings.dictation-meetings-and-files-share"))
          .font(AppStyle.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var startupSettings: some View {
    SettingsFormPage(
      title: L10n.text("settings.startup"),
      subtitle: L10n.text("settings.choose-whether-the-app-opens")
    ) {
      SettingsSection(L10n.text("settings.open-at-login-label")) { loginToggle }
    }
  }

}
