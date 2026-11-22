import SwiftUI

enum DesignTokens {
  enum Spacing {
    static let none: CGFloat = 0
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let page: CGFloat = 20
  }
  enum Radius {
    static let navigation: CGFloat = 8
    static let editor: CGFloat = 8
    static let control: CGFloat = 8
    static let panel: CGFloat = 12
  }
  enum Layout {
    static let sidebarIdealWidth: CGFloat = 228
    static let sidebarMinimumWidth: CGFloat = 180
    static let sidebarMaximumWidth: CGFloat = 290
    static let settingsSidebarIdealWidth: CGFloat = 220
    static let settingsContentMaximumWidth: CGFloat = 860
    static let historySidebarIdealWidth: CGFloat = 240
    static let transcriptMinimumHeight: CGFloat = 165
    static let transcriptCompactHeight: CGFloat = 320
    static let transcriptViewportFraction: CGFloat = 0.6
    static let meetingTranscriptHeight: CGFloat = 220
    static let screenMinimumWidth: CGFloat = 800
    static let screenMinimumHeight: CGFloat = 540
    static let recordingPanelWidth: CGFloat = 500
    static let recordingHUDIconWidth: CGFloat = 72
    static let recordingHUDIconHeight: CGFloat = 34
    static let aboutBrandMarkSize: CGFloat = 72
    static let featureIconSize: CGFloat = 28
    static let speakerNameMaximumHeight: CGFloat = 100
    static let recordingPanelRadius: CGFloat = 18
    static let recordingPanelHeight: CGFloat = 170
    static let editorMinimumHeight: CGFloat = 160
  }
  enum Typography {
    static let title = Font.title2.weight(.semibold)
    static let section = Font.headline
    static let body = Font.body
    static let detail = Font.subheadline
    static let caption = Font.caption
  }
  enum Motion {
    static let sectionChange = Animation.easeInOut(duration: 0.18)
  }
  enum Colors {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let editor = Color(nsColor: .textBackgroundColor)
    static let error = Color(nsColor: .systemRed)
    static let warning = Color(nsColor: .systemOrange)
  }
}
