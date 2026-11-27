import AppKit
import DictCore
import ServiceManagement
import SwiftUI

struct RecordingView: View {
  @ObservedObject var controller: DictationSession

  var body: some View {
    VStack(spacing: DesignTokens.Spacing.s) {
      HStack(spacing: DesignTokens.Spacing.s) {
        if controller.phase == .recording {
          HStack(alignment: .center, spacing: DesignTokens.Spacing.xxs) {
            ForEach(0..<12, id: \.self) { index in
              Capsule().fill(Color.accentColor).frame(
                width: 3,
                height: CGFloat(5 + controller.level * Float(10 + (index * 7) % 23)))
            }
          }.frame(
            width: DesignTokens.Layout.recordingHUDIconWidth,
            height: DesignTokens.Layout.recordingHUDIconHeight
          ).animation(
            .easeOut(duration: 0.15), value: controller.level)
          Text(String(format: "%02d:%02d", controller.elapsed / 60, controller.elapsed % 60))
            .monospacedDigit()
          if controller.elapsed >= 29 * 60 {
            Text(L10n.text("recording.less-than-a-minute-left")).font(AppStyle.caption)
              .foregroundStyle(.orange)
          }
        } else if controller.phase == .processing {
          ProgressView().controlSize(.small)
        } else if controller.busyNotice != nil {
          Image(systemName: "info.circle.fill").foregroundStyle(Color.secondary)
            .accessibilityHidden(true)
        } else if controller.phase == .result {
          Image(
            systemName: controller.noticeIsSuccess
              ? "checkmark.circle.fill" : "info.circle.fill"
          )
          .foregroundStyle(controller.noticeIsSuccess ? Color.green : Color.secondary)
          .accessibilityHidden(true)
        }
        Text(controller.busyNotice ?? controller.message).font(AppStyle.body).lineLimit(3)
        Spacer(minLength: 0)
        if controller.phase == .recording && controller.handsFree {
          Button(L10n.text("recording.finish")) {
            UsageTelemetry.action(.dictation, .stopDictation)
            controller.finish()
          }
          .buttonStyle(.borderedProminent)
        }
        if controller.phase == .recording && controller.handsFree {
          Text(L10n.text("recording.esc-cancel"))
            .font(AppStyle.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help(L10n.text("recording.press-escape-to-cancel-recording"))
        }
        Button {
          if controller.phase == .result {
            UsageTelemetry.action(.dictation, .dismissResult)
            controller.dismissResult()
          } else {
            UsageTelemetry.action(.dictation, .cancelDictation)
            controller.cancel()
          }
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
          controller.phase == .result
            ? L10n.text("recording.dismiss-notification") : L10n.text("recording.cancel-recording")
        )
        .help(
          controller.phase == .result
            ? L10n.text("recording.dismiss-notification")
            : L10n.text("recording.cancel-and-delete-recording"))
      }
      if let transcript = controller.transcript,
        !transcript.segments.isEmpty,
        controller.phase == .recording || controller.phase == .processing
      {
        TranscriptResultView(transcript: transcript).frame(
          maxHeight: DesignTokens.Layout.recordingPanelHeight)
      }
    }
    .padding(DesignTokens.Spacing.m).frame(width: DesignTokens.Layout.recordingPanelWidth)
    .background(
      .regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Layout.recordingPanelRadius)
    )
  }
}
