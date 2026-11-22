import SwiftUI

struct WorkspaceHeader: View {
  let title: String
  var subtitle: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
      Text(title).font(DesignTokens.Typography.title)
      if let subtitle {
        Text(subtitle)
          .font(DesignTokens.Typography.detail)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct WorkspaceStatusBanner: View {
  enum Kind { case info, success, warning, error }
  let message: String
  var kind: Kind = .info

  private var symbol: String {
    switch kind {
    case .info: "info.circle"
    case .success: "checkmark.circle"
    case .warning: "exclamationmark.triangle"
    case .error: "xmark.circle"
    }
  }

  private var tint: Color {
    switch kind {
    case .info: .secondary
    case .success: .green
    case .warning: DesignTokens.Colors.warning
    case .error: DesignTokens.Colors.error
    }
  }

  var body: some View {
    Label {
      Text(message)
        .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: symbol).accessibilityHidden(true)
    }
    .font(DesignTokens.Typography.detail)
    .foregroundStyle(tint)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

#Preview("WorkspaceHeader • light") {
  WorkspaceHeader(
    title: L10n.text("menu.dictation-label"),
    subtitle: L10n.text("workspace.recognition-stays-on-your-mac")
  )
  .padding(DesignTokens.Spacing.l)
  .frame(width: 520)
  .preferredColorScheme(.light)
}

#Preview("WorkspaceStatusBanner • dark") {
  VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
    WorkspaceStatusBanner(message: L10n.text("workspace.done"), kind: .success)
    WorkspaceStatusBanner(
      message: L10n.text("workspace.microphone-access-required"), kind: .warning)
    WorkspaceStatusBanner(message: L10n.text("workspace.could-not-save-changes"), kind: .error)
  }
  .padding(DesignTokens.Spacing.l)
  .frame(width: 520)
  .preferredColorScheme(.dark)
}

struct SettingsFormPage<Content: View>: View {
  let title: String
  let subtitle: String?
  let content: Content

  init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
        WorkspaceHeader(title: title, subtitle: subtitle)
          .accessibilityAddTraits(.isHeader)
        content
      }
      .frame(maxWidth: DesignTokens.Layout.settingsContentMaximumWidth, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, DesignTokens.Spacing.page)
      .padding(.vertical, DesignTokens.Spacing.l)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DesignTokens.Colors.window)
  }
}

struct SettingsSection<Content: View>: View {
  let title: String
  let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
      Text(title)
        .font(DesignTokens.Typography.section)
        .accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(DesignTokens.Spacing.m)
      .background(
        DesignTokens.Colors.surface,
        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct SettingsToggleRow: View {
  let title: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: DesignTokens.Spacing.m) {
      Text(title)
      Spacer(minLength: DesignTokens.Spacing.xs)
      Toggle(title, isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
    }
  }
}

#Preview("Settings form • dark") {
  SettingsFormPage(title: L10n.text("settings.general")) {
    SettingsSection(L10n.text("menu.dictation-label")) {
      Text(L10n.text("menu.dictation-enabled"))
      Text(L10n.text("settings.use-the-shortcut-to-insert"))
        .font(DesignTokens.Typography.caption)
        .foregroundStyle(.secondary)
    }
    SettingsSection(L10n.text("settings.readiness")) {
      Text(L10n.text("settings.parakeet-ultra-is-ready"))
    }
  }
  .frame(width: 720, height: 560)
  .preferredColorScheme(.dark)
}

#Preview("Settings form • light") {
  SettingsFormPage(title: L10n.text("settings.general")) {
    SettingsSection(L10n.text("menu.dictation-label")) { Text(L10n.text("menu.dictation-enabled")) }
    SettingsSection(L10n.text("settings.readiness")) {
      Text(L10n.text("settings.parakeet-ultra-is-ready"))
    }
  }
  .frame(width: 720, height: 560)
  .preferredColorScheme(.light)
}
