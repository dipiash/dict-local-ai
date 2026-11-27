import DictApplication
import SwiftUI

struct ModelsView: View {
  let speechReady: Bool
  let speakerModelsReady: Bool
  let installing: Bool
  let progress: Double?
  let message: String
  let installDisabled: Bool
  let modelRevision: @MainActor (ManagedModel) -> String?
  let installModel: @MainActor (ManagedModel) -> Void

  var body: some View {
    SettingsFormPage(
      title: L10n.text("settings.models"),
      subtitle: L10n.text("models.manage-on-device-speech-recognition")
    ) {
      Text(
        L10n.text("models.models-are-downloaded-from-hugging")
      )
      .font(AppStyle.caption).foregroundStyle(.secondary)
      SettingsSection("Parakeet Ultra") {
        modelCard(
          kind: .ultra,
          ready: speechReady,
          detail: L10n.text("models.speech-recognition-for-dictation-meetings"))
      }
      SettingsSection("Nemotron 3 · fast32 + fast128") {
        modelCard(
          kind: .nemotron,
          ready: speakerModelsReady,
          detail:
            L10n.text("models.speaker-labels-for-files-fast128")
        )
      }
      SettingsSection(L10n.text("models.status")) {
        if installing {
          if let value = progress {
            ProgressView(value: value).accessibilityIdentifier("models-download-progress")
            Text("\(Int(value * 100))%").monospacedDigit()
          } else {
            ProgressView().accessibilityIdentifier("models-download-progress")
          }
        }
        Text(message).font(AppStyle.caption).foregroundStyle(.secondary)
        Text(
          L10n.text("models.the-app-records-the-hugging")
        )
        .font(AppStyle.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func modelCard(kind: ManagedModel, ready: Bool, detail: String) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
      HStack(spacing: DesignTokens.Spacing.s) {
        Image(systemName: ready ? "checkmark.circle.fill" : "arrow.down.circle")
          .foregroundStyle(ready ? Color.green : Color.secondary)
        Text(ready ? L10n.text("models.ready") : L10n.text("models.installation-required"))
          .font(AppStyle.body)
        Spacer(minLength: DesignTokens.Spacing.xs)
      }
      Text(detail).font(AppStyle.caption).foregroundStyle(.secondary)
      HStack {
        if let revision = modelRevision(kind) {
          Text("HF SHA: \(revision.prefix(12))")
            .font(AppStyle.caption).monospaced().foregroundStyle(.secondary)
        }
        Spacer()
        Button(ready ? L10n.text("models.reinstall") : L10n.text("models.download")) {
          UsageTelemetry.action(.models, ready ? .modelReinstall : .modelInstall)
          installModel(kind)
        }
        .disabled(installDisabled)
        .accessibilityIdentifier("install-model-\(kind.rawValue)")
      }
    }
    .padding(.vertical, DesignTokens.Spacing.xxs)
  }
}
