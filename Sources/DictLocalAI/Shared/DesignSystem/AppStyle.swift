import SwiftUI

enum AppStyle {
  static let title = DesignTokens.Typography.title
  static let section = DesignTokens.Typography.section
  static let body = DesignTokens.Typography.body
  static let caption = DesignTokens.Typography.caption
  static let spacing = DesignTokens.Spacing.s
  static let pagePadding = DesignTokens.Spacing.page
}

private struct AppPanel: ViewModifier {
  func body(content: Content) -> some View {
    content.background(
      Color(nsColor: .controlBackgroundColor),
      in: RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous))
  }
}

extension View {
  func appPanel() -> some View { modifier(AppPanel()) }
}

struct AppPanelGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: AppStyle.spacing) {
      configuration.label.font(AppStyle.section)
      configuration.content.frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(DesignTokens.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .appPanel()
  }
}

struct AppEmptyState: View {
  let title: String
  let symbol: String
  let message: String

  var body: some View {
    VStack(spacing: AppStyle.spacing) {
      Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
      Text(title).font(AppStyle.section)
      Text(message).font(AppStyle.body).foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }.padding(AppStyle.pagePadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }
}

#Preview("Empty state in light mode") {
  AppEmptyState(
    title: L10n.text("history.no-records"), symbol: "clock",
    message: L10n.text("history.history-is-empty")
  )
  .frame(width: 640, height: 440)
  .preferredColorScheme(.light)
}

#Preview("Empty state in dark mode") {
  AppEmptyState(
    title: L10n.text("history.no-records"), symbol: "clock",
    message: L10n.text("history.history-is-empty")
  )
  .frame(width: 640, height: 440)
  .preferredColorScheme(.dark)
}
