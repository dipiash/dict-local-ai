import DictCore
import SwiftUI

struct FileTranscriptionView: View {
  @ObservedObject var controller: FileTranscriptionSession
  let speechReady: Bool
  let speakerModelsReady: Bool
  @State private var confirmReplace = false
  @State private var confirmRetry = false
  @State private var mergeCandidateIndex: Int?

  private var hasReview: Bool {
    !controller.running
      && (!controller.reviewCandidates.isEmpty || !controller.splitCandidates.isEmpty)
  }

  // Two expanding layouts can blank the sidebar on macOS.
  var body: some View {
    GeometryReader { viewport in
      VStack(alignment: .leading, spacing: AppStyle.spacing) {
        ScrollView(.vertical) {
          VStack(alignment: .leading, spacing: AppStyle.spacing) {
            fileControls
            if let transcript = controller.transcript {
              transcriptPane(
                transcript,
                height: max(
                  DesignTokens.Layout.transcriptCompactHeight,
                  viewport.size.height * DesignTokens.Layout.transcriptViewportFraction
                ))
              reviewPanels
            }
          }
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
        .accessibilityIdentifier("files-page-scroll")
        footer
      }
      .padding(AppStyle.pagePadding)
      .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .groupBoxStyle(AppPanelGroupBoxStyle())
    .onAppear {
      DiagnosticLog.shared.event(
        "files-ui", "page_appeared", "has_transcript=\(controller.transcript != nil)")
    }
    .onDisappear { DiagnosticLog.shared.event("files-ui", "page_disappeared") }
    .confirmationDialog(L10n.text("files.replace-the-current-result"), isPresented: $confirmReplace)
    {
      Button(L10n.text("files.choose-another-file"), role: .destructive) {
        UsageTelemetry.action(.files, .replaceFile)
        controller.chooseFile()
      }
    } message: {
      Text(
        L10n.text("files.save-any-text-you-want")
      )
    }
    .confirmationDialog(
      L10n.text("files.confirm-these-segments-have-the"),
      isPresented: Binding(
        get: { mergeCandidateIndex != nil },
        set: { if !$0 { mergeCandidateIndex = nil } }
      )
    ) {
      Button(L10n.text("files.merge-this-episode-only")) {
        if let index = mergeCandidateIndex { controller.confirmSameSpeaker(index) }
        mergeCandidateIndex = nil
      }
      Button(L10n.text("menu.cancel"), role: .cancel) {
        UsageTelemetry.action(.files, .dismissSpeakerMerge)
        mergeCandidateIndex = nil
      }
    } message: {
      Text(
        L10n.text("files.listen-at-the-marked-timestamp")
      )
    }
    .alert(L10n.text("files.process-this-file-again"), isPresented: $confirmRetry) {
      Button(L10n.text("menu.cancel"), role: .cancel) {}
      Button(L10n.text("files.process-again-and-replace"), role: .destructive) {
        controller.retryFile()
      }
    } message: {
      Text(
        L10n.text("files.the-current-unsaved-text-will")
      )
    }
  }

  private var fileControls: some View {
    VStack(alignment: .leading, spacing: AppStyle.spacing) {
      WorkspaceHeader(
        title: L10n.text("menu.files-label"),
        subtitle: L10n.text("files.turn-audio-files-into-text"))
      GroupBox {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
          Text(L10n.text("files.up-to-3-hours-on")).foregroundStyle(.secondary)
          Text(L10n.text("files.recognition-parakeet-ultra"))
            .font(AppStyle.caption).foregroundStyle(.secondary)
          Toggle(
            L10n.text("files.identify-speakers-across-the-full"), isOn: $controller.identifySpeakers
          )
          .disabled(controller.running)
          .onChange(of: controller.identifySpeakers) { _, enabled in
            UsageTelemetry.action(.files, .toggleSpeakers, value: enabled)
          }
          if controller.identifySpeakers {
            Toggle(
              L10n.text("files.check-for-possible-speaker-merges"),
              isOn: $controller.compareChunks
            )
            .disabled(controller.running)
            .onChange(of: controller.compareChunks) { _, enabled in
              UsageTelemetry.action(.files, .toggleSpeakerReview, value: enabled)
            }
            Text(L10n.text("files.independent-3-and-10-minute"))
              .font(AppStyle.caption).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          if !speechReady || (controller.identifySpeakers && !speakerModelsReady) {
            WorkspaceStatusBanner(
              message: L10n.text("files.install-parakeet-ultra-and-nemotron"),
              kind: .warning)
          }
          HStack {
            Button(L10n.text("files.choose-file")) {
              UsageTelemetry.action(.files, .chooseFile)
              if controller.transcript?.processedUntil ?? 0 > 0 {
                confirmReplace = true
              } else {
                controller.chooseFile()
              }
            }
            .disabled(
              controller.running || !speechReady
                || (controller.identifySpeakers && !speakerModelsReady))
            if controller.running {
              Button(L10n.text("menu.undo")) {
                UsageTelemetry.action(.files, .cancelFile)
                controller.cancel()
              }
            }
          }
          Text(controller.message)
            .fixedSize(horizontal: false, vertical: true)
          if controller.canRetry && !controller.running {
            Button(L10n.text("files.process-this-file-again-label")) {
              UsageTelemetry.action(.files, .retryFile)
              confirmRetry = true
            }
            .buttonStyle(.borderedProminent)
            Text(L10n.text("files.processing-the-file-again-replaces"))
              .font(AppStyle.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func transcriptPane(_ transcript: FileTranscript, height: CGFloat) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
        Text(transcript.source).font(AppStyle.section).lineLimit(2)
        if controller.running && transcript.duration == 0 { ProgressView() }
        if transcript.duration > 0 {
          ProgressView(value: transcript.processedUntil, total: transcript.duration)
          if controller.running && transcript.processedUntil >= transcript.duration {
            ProgressView(L10n.text("files.identifying-speakers")).controlSize(.small)
          }
          Text(
            L10n.text(
              "files.processed-time", "\(FileTranscript.time(transcript.processedUntil))",
              "\(FileTranscript.time(transcript.duration))")
          )
          .font(AppStyle.caption).monospacedDigit()
        }
        if let warnings = transcript.asrWarnings, !warnings.isEmpty {
          ForEach(warnings, id: \.self) { warning in
            Text(warning).font(AppStyle.caption).foregroundStyle(.orange)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        TranscriptResultView(
          transcript: transcript, usageScreen: .files, editable: !controller.running,
          rename: { controller.renameSpeaker($0, name: $1) },
          assignSpeaker: { controller.assignSpeaker($0, $1) },
          addSpeaker: { controller.addSpeaker($0) }
        )
        .frame(minHeight: DesignTokens.Layout.transcriptMinimumHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
  }

  @ViewBuilder private var reviewPanels: some View {
    if !controller.reviewCandidates.isEmpty && !controller.running {
      GroupBox(L10n.text("files.review-speaker-changes")) {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
          ForEach(controller.reviewCandidates.indices, id: \.self) { index in
            let item = controller.reviewCandidates[index]
            Text(
              L10n.text(
                "files.comparison-windows", "\(FileTranscript.segmentTime(item.start))",
                "\(FileTranscript.segmentTime(item.end))",
                "\(Int(item.metrics["independentWindows"] ?? 1))")
            )
            .font(AppStyle.caption).monospacedDigit()
          }
          Text(
            L10n.text("files.these-are-suggestions-listen-to")
          )
          .font(AppStyle.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    if !controller.splitCandidates.isEmpty && !controller.running {
      GroupBox(L10n.text("files.one-speaker-may-have-been")) {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
          ForEach(controller.splitCandidates.indices, id: \.self) { index in
            let item = controller.splitCandidates[index]
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
              Text(
                "\(FileTranscript.segmentTime(item.transition)) · \(item.beforeSpeaker) → \(item.afterSpeaker)"
              )
              .font(AppStyle.caption).monospacedDigit()
              Text(
                L10n.text(
                  "files.matching-independent-windows-listen-to", Int64(item.supportingWindows))
              )
              .font(AppStyle.caption).foregroundStyle(.secondary)
              Button(L10n.text("files.same-person")) {
                UsageTelemetry.action(.files, .confirmSpeakerMerge)
                mergeCandidateIndex = index
              }
            }
          }
          Text(
            L10n.text("files.this-updates-only-the-complete")
          )
          .font(AppStyle.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
      Divider()
      TranscriptActionBar(
        enabled: !controller.running && (controller.transcript?.processedUntil ?? 0) > 0,
        copy: {
          UsageTelemetry.action(.files, .copyTranscript)
          if let transcript = controller.transcript { TextInsertion.copy(transcript.plainText) }
        },
        exportTXT: {
          UsageTelemetry.action(.files, .exportTXT)
          controller.save("txt")
        },
        exportJSON: {
          UsageTelemetry.action(.files, .exportJSON)
          controller.save("json")
        },
        exportAudit: controller.audit == nil || controller.running
          ? nil
          : {
            UsageTelemetry.action(.files, .exportAudit)
            controller.saveAudit()
          })
      Text(
        L10n.text("files.timestamps-are-approximate-and-start")
      )
      .font(AppStyle.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("file-export-footer")
  }
}
