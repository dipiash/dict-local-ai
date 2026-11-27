import DictApplication
import SwiftUI

/// Size of the saved history audio and the button that deletes all of it.
struct AudioStorageControls: View {
  @ObservedObject var history: HistoryStore
  @State private var confirmRemoval = false

  private var summary: String {
    if history.audioUsageFailed { return L10n.text("settings.audio-usage-failed") }
    guard let usage = history.audioUsage else { return L10n.text("settings.audio-usage-counting") }
    let megabytes = usage.bytes == 0 ? 0 : max(1, Int((Double(usage.bytes) / 1_048_576).rounded()))
    return L10n.text(
      "settings.audio-usage", L10n.text("settings.audio-size", megabytes),
      L10n.text("settings.audio-files", usage.files))
  }

  var body: some View {
    Text(summary)
      .accessibilityIdentifier("settings-audio-usage")
      .onAppear { history.reloadAudioStorageUsage() }
    Button(L10n.text("settings.remove-all-audio"), role: .destructive) {
      UsageTelemetry.action(.settings, .removeAllAudioPrompt)
      confirmRemoval = true
    }
    .disabled(history.removingAudio)
    .accessibilityIdentifier("settings-remove-all-audio")
    .confirmationDialog(
      L10n.text("settings.remove-all-audio-title"), isPresented: $confirmRemoval
    ) {
      Button(L10n.text("settings.remove-all-audio-confirm"), role: .destructive) {
        UsageTelemetry.action(.settings, .removeAllAudioConfirm)
        history.clearSavedAudio()
      }
    } message: {
      Text(L10n.text("settings.remove-all-audio-message"))
    }
    if let message = history.audioRemovalError {
      Text(message).font(AppStyle.caption).foregroundStyle(.red)
    }
  }
}
