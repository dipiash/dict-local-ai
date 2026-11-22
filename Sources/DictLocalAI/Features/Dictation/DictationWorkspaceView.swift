import AppKit
import DictCore
import ServiceManagement
import SwiftUI

struct DictationWorkspaceView: View {
  @ObservedObject var controller: DictationSession
  @ObservedObject var preferences: Preferences
  @FocusState private var editorFocused: Bool

  private var hasRecoverableAudio: Bool {
    controller.phase == .failed || controller.phase == .interrupted
  }

  private var shortcutHint: String {
    L10n.text(
      "dictation.editor-instructions", preferences.hold.displayLabel,
      preferences.toggle.displayLabel)
  }

  var body: some View {
    GeometryReader { geometry in
      VStack(alignment: .leading, spacing: AppStyle.spacing) {
        WorkspaceHeader(title: L10n.text("menu.dictation-label"), subtitle: shortcutHint)
        HStack(spacing: DesignTokens.Spacing.xs) {
          Text(L10n.text("dictation.dictation-editor")).font(AppStyle.section)
          Spacer(minLength: 0)
          Button(L10n.text("menu.copy")) {
            UsageTelemetry.action(.dictation, .manualCopy)
            if controller.scratchpad.isEmpty {
              controller.copyResult()
            } else {
              TextInsertion.copy(controller.scratchpad)
            }
          }
          .disabled(!controller.canExportTXT)
          .help(L10n.text("dictation.editor-text-or-the-latest"))
          Button(L10n.text("dictation.clear")) {
            UsageTelemetry.action(.dictation, .clearScratchpad)
            controller.scratchpad = ""
          }
          .disabled(controller.scratchpad.isEmpty)
          Menu(L10n.text("dictation.export")) {
            Button(L10n.text("dictation.txt-plain-text")) {
              UsageTelemetry.action(.dictation, .exportTXT)
              controller.save("txt")
            }
            .disabled(!controller.canExportTXT)
            .help(
              L10n.text("dictation.editor-text-without-timestamps-or")
            )
            Button(L10n.text("dictation.json-timestamps-and-speakers")) {
              UsageTelemetry.action(.dictation, .exportJSON)
              controller.save("json")
            }
            .disabled(!controller.canExportJSON)
            .help(
              L10n.text("dictation.the-latest-dictation-with-timestamps")
            )
          }
          .disabled(!controller.canExportTXT && !controller.canExportJSON)
          .help(
            L10n.text("dictation.txt-contains-plain-editor-text")
          )
          .accessibilityIdentifier("dictation-export-menu")
        }
        if controller.phase == .recording || controller.phase == .processing {
          HStack(spacing: DesignTokens.Spacing.xs) {
            ProgressView().controlSize(.small)
            Text(controller.message).foregroundStyle(.secondary)
          }
        } else if hasRecoverableAudio {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            WorkspaceStatusBanner(message: controller.message, kind: .error)
            HStack(spacing: DesignTokens.Spacing.xs) {
              Button(L10n.text("dictation.process-again")) {
                UsageTelemetry.action(.dictation, .retryDictation)
                controller.retry()
              }
              Button(L10n.text("dictation.delete-recording"), role: .destructive) {
                UsageTelemetry.action(.dictation, .dismissResult)
                controller.dismissResult()
              }
            }
          }
        } else if controller.phase == .result
          && (!controller.noticeIsSuccess || controller.text.isEmpty)
        {
          HStack(spacing: DesignTokens.Spacing.s) {
            WorkspaceStatusBanner(message: controller.message, kind: .warning)
            if controller.text.isEmpty {
              Button(L10n.text("settings.open-settings")) {
                UsageTelemetry.action(.dictation, .openPrivacySettings)
                controller.onOpenSettings()
              }
            }
          }
        }
        ZStack(alignment: .topLeading) {
          TextEditor(text: $controller.scratchpad)
            .focused($editorFocused)
            .font(AppStyle.body)
            .scrollContentBackground(.hidden)
            .padding(DesignTokens.Spacing.xs)
            .accessibilityIdentifier("dictation-scratchpad")
            .accessibilityLabel(L10n.text("dictation.dictation-field"))
          if controller.scratchpad.isEmpty {
            Text(L10n.text("dictation.speak-or-type-here"))
              .font(AppStyle.body)
              .foregroundStyle(.tertiary)
              .padding(.top, DesignTokens.Spacing.xs)
              .padding(.leading, DesignTokens.Spacing.xs + 5)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .background(DesignTokens.Colors.editor)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.editor, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: DesignTokens.Radius.editor, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.25))
        }
        .frame(minHeight: DesignTokens.Layout.editorMinimumHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
      }
      .padding(AppStyle.pagePadding)
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    }
    .onChange(of: editorFocused) { _, focused in
      controller.internalEditorFocused = focused
    }
    .onDisappear { controller.internalEditorFocused = false }
  }
}
