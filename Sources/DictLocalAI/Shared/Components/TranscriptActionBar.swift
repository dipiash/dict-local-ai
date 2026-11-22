import SwiftUI

struct TranscriptActionBar: View {
  let enabled: Bool
  let copy: () -> Void
  let exportTXT: () -> Void
  let exportJSON: () -> Void
  var saveChanges: (() -> Void)? = nil
  var exportAudit: (() -> Void)? = nil

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: DesignTokens.Spacing.xs) { buttons }
        .fixedSize(horizontal: true, vertical: false)
      Menu(L10n.text("transcript.transcript-actions")) { buttons }
    }
    .disabled(!enabled)
    .accessibilityIdentifier("transcript-action-bar")
  }

  @ViewBuilder private var buttons: some View {
    if let saveChanges { Button(L10n.text("transcript.save-changes"), action: saveChanges) }
    Button(L10n.text("menu.copy"), action: copy)
    Button("TXT…", action: exportTXT)
    Button("JSON…", action: exportJSON)
    if let exportAudit { Button(L10n.text("transcript.diagnostics-json"), action: exportAudit) }
  }
}

#Preview("Actions in light mode") {
  TranscriptActionBar(enabled: true, copy: {}, exportTXT: {}, exportJSON: {})
    .padding(DesignTokens.Spacing.m)
    .frame(width: 520)
    .preferredColorScheme(.light)
}

#Preview("Actions in dark mode") {
  TranscriptActionBar(enabled: false, copy: {}, exportTXT: {}, exportJSON: {})
    .padding(DesignTokens.Spacing.m)
    .frame(width: 260)
    .preferredColorScheme(.dark)
}
