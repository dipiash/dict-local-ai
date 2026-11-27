import DictCore
import SwiftUI

struct MeetingView: View {
  @ObservedObject var controller: MeetingSession
  @ObservedObject var preferences: Preferences
  @ObservedObject var models: AppServices
  private enum Confirmation: Identifiable {
    case newMeeting
    var id: String { "new" }
  }

  @State private var confirmation: Confirmation?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppStyle.spacing) {
        WorkspaceHeader(
          title: L10n.text("menu.meetings-label"),
          subtitle: L10n.text("meeting.record-system-audio-and-turn"))
        GroupBox {
          VStack(alignment: .leading, spacing: AppStyle.spacing) {
            Label(L10n.text("meeting.system-audio"), systemImage: "speaker.wave.2")
              .font(AppStyle.section)
              .accessibilityIdentifier("meeting-system-audio-only")
            Text(
              L10n.text("meeting.records-only-audio-playing-on")
            )
            .font(AppStyle.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if !models.speakerModelsReady {
              WorkspaceStatusBanner(
                message: L10n.text("meeting.nemotron-3-is-not-ready"),
                kind: .warning)
            }
            HStack {
              if controller.running {
                Button(
                  controller.state == .preparing
                    ? L10n.text("meeting.cancel-setup") : L10n.text("recording.finish")
                ) {
                  UsageTelemetry.action(.meeting, .stopMeeting)
                  controller.stop()
                }
                .disabled(controller.state == .finishing)
                Text(FileTranscript.time(Double(controller.elapsed))).monospacedDigit()
                if controller.elapsed >= 179 * 60 {
                  Text(L10n.text("meeting.less-than-a-minute-left")).foregroundStyle(.orange)
                }
              } else {
                Button(L10n.text("meeting.start-meeting")) {
                  UsageTelemetry.action(.meeting, .startMeeting)
                  if controller.unsaved { confirmation = .newMeeting } else { controller.start() }
                }.buttonStyle(.borderedProminent)
                  .disabled(!models.ready || !models.speakerModelsReady)

              }
            }
            if let progress = controller.progress { ProgressView(value: progress) }
            if controller.running {
              Text(
                controller.systemAudioDetected
                  ? L10n.text("meeting.the-app-received-system-audio")
                  : L10n.text("meeting.waiting-for-system-audio-play")
              )
              .font(AppStyle.caption)
              .foregroundStyle(controller.systemAudioDetected ? .green : .secondary)
            }
            if controller.running, let minutes = controller.systemAudioSilenceMinutes {
              WorkspaceStatusBanner(
                message: L10n.text("meeting.system-audio-silent", minutes), kind: .warning)
            }
            Text(controller.message).font(AppStyle.body)
            if !controller.saveError.isEmpty { Text(controller.saveError).foregroundStyle(.red) }
            Text(
              preferences.saveHistory
                ? L10n.text("meeting.text-is-saved-locally-for")
                : L10n.text("meeting.autosave-is-off-unsaved-text")
            )
            .font(AppStyle.caption)
          }
        }
        if let transcript = controller.transcript {
          GroupBox {
            VStack(alignment: .leading, spacing: AppStyle.spacing) {
              TranscriptResultView(
                transcript: transcript, usageScreen: .meeting, editable: !controller.running,
                rename: controller.rename, editText: controller.editSegment
              )
              .frame(height: DesignTokens.Layout.meetingTranscriptHeight)
              TranscriptActionBar(
                enabled: !controller.running && transcript.processedUntil > 0,
                copy: {
                  UsageTelemetry.action(.meeting, .copyTranscript)
                  TextInsertion.copy(transcript.plainText)
                },
                exportTXT: {
                  UsageTelemetry.action(.meeting, .exportTXT)
                  controller.save("txt")
                },
                exportJSON: {
                  UsageTelemetry.action(.meeting, .exportJSON)
                  controller.save("json")
                },
                saveChanges: controller.running
                  || (!controller.unsaved && controller.selectedMeeting != nil)
                  ? nil
                  : {
                    UsageTelemetry.action(.meeting, .saveEdits)
                    controller.saveChanges()
                  },
                exportAudit: controller.audit == nil
                  ? nil
                  : {
                    UsageTelemetry.action(.meeting, .exportAudit)
                    controller.saveAudit()
                  })
            }
          }
        }
        Divider()
        Text(
          L10n.text("meeting.saved-meetings-dictation-and-transcribed")
        )
        .font(AppStyle.caption).foregroundStyle(.secondary)

      }.padding(AppStyle.pagePadding)
    }
    .groupBoxStyle(AppPanelGroupBoxStyle())
    .alert(item: $confirmation) { _ in
      Alert(
        title: Text(L10n.text("meeting.replace-the-unsaved-result")),
        message: Text(L10n.text("meeting.unsaved-changes-to-the-current")),
        primaryButton: .destructive(Text(L10n.text("meeting.start-new-meeting"))) {
          UsageTelemetry.action(.meeting, .confirmNewMeeting)
          controller.start()
        },
        secondaryButton: .cancel(Text(L10n.text("menu.cancel"))) {
          UsageTelemetry.action(.meeting, .cancelNewMeeting)
        })
    }

  }
}

struct MeetingRecordingView: View {
  @ObservedObject var controller: MeetingSession
  @ObservedObject var dictation: DictationSession
  var body: some View {
    VStack(spacing: DesignTokens.Spacing.s) {
      if let notice = dictation.busyNotice {
        Text(notice).font(AppStyle.body).lineLimit(2)
      }
      controls
    }.padding(DesignTokens.Spacing.m).background(
      .regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Layout.recordingPanelRadius)
    )
  }
  private var controls: some View {
    HStack(spacing: DesignTokens.Spacing.m) {
      Image(systemName: "waveform").symbolEffect(.pulse, options: .repeating)
      Text(L10n.text("meeting.meeting", "\(FileTranscript.time(Double(controller.elapsed)))"))
        .monospacedDigit()
      if controller.elapsed >= 179 * 60 {
        Text(L10n.text("meeting.less-than-a-minute-until")).foregroundStyle(.orange)
      }
      Button(L10n.text("recording.finish")) {
        UsageTelemetry.action(.meeting, .stopMeeting)
        controller.stop()
      }.disabled(controller.state == .finishing)
    }
  }
}
