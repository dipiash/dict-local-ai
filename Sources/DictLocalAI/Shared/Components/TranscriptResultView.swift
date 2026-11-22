import DictCore
import SwiftUI

struct TranscriptResultView: View {
  let transcript: FileTranscript
  var usageScreen: UsageTelemetry.Screen = .workspace
  var editable = false
  var rename: (String, String) -> Void = { _, _ in }
  var editText: ((Int, String) -> Void)?
  var assignSpeaker: ((Int, String?) -> Void)?
  var addSpeaker: ((Int) -> Void)?
  var body: some View {
    VStack(alignment: .leading) {
      if editable && !transcript.speakerIDs.isEmpty {
        DisclosureGroup(L10n.text("transcript.speaker-names")) {
          ScrollView {
            ForEach(transcript.speakerIDs, id: \.self) { id in
              VStack(alignment: .leading) {
                TextField(
                  transcript.speakerTitle(id),
                  text: Binding(
                    get: { transcript.speakerNames[id] ?? "" }, set: { rename(id, $0) })
                )
                .onSubmit { UsageTelemetry.action(usageScreen, .confirmSpeakerName) }
                if let candidate = transcript.speakerNameSuggestions[id],
                  (transcript.speakerNames[id] ?? "").isEmpty
                {
                  Button(L10n.text("transcript.confirm-name", "\(candidate)")) {
                    UsageTelemetry.action(usageScreen, .confirmSpeakerName)
                    rename(id, candidate)
                  }.font(
                    AppStyle.caption)
                }
              }
            }
          }.frame(maxHeight: DesignTokens.Layout.speakerNameMaximumHeight)
        }
      }
      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: AppStyle.spacing) {
          ForEach(transcript.segments.indices, id: \.self) { index in
            let segment = transcript.segments[index]
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
              Text(
                "\(FileTranscript.segmentTime(segment.start))–\(FileTranscript.segmentTime(segment.end))"
                  + (transcript.speakerRecognitionEnabled == false
                    ? "" : " · \(transcript.speakerTitle(segment.speakerID))")
                  + (segment.channel.map {
                    $0 == "microphone"
                      ? L10n.text("transcript.microphone") : L10n.text("transcript.system-audio")
                  } ?? "")
              )
              .font(AppStyle.caption).foregroundStyle(.secondary)
              if editable, transcript.speakerRecognitionEnabled != false,
                let assignSpeaker, let addSpeaker
              {
                Menu(L10n.text("transcript.change-speaker")) {
                  ForEach(transcript.speakerIDs, id: \.self) { speaker in
                    Button(transcript.speakerTitle(speaker)) {
                      UsageTelemetry.action(usageScreen, .assignSpeaker)
                      assignSpeaker(index, speaker)
                    }
                  }
                  Divider()
                  Button(L10n.text("transcript.new-speaker")) {
                    UsageTelemetry.action(usageScreen, .addSpeaker)
                    addSpeaker(index)
                  }
                  Button(L10n.text("transcript.unknown-speaker")) {
                    UsageTelemetry.action(usageScreen, .clearSpeaker)
                    assignSpeaker(index, nil)
                  }
                }
                .font(AppStyle.caption)
              }
              if editable, let editText {
                TextField(
                  L10n.text("transcript.segment-text"),
                  text: Binding(
                    get: { segment.text }, set: { editText(index, $0) }), axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { UsageTelemetry.action(usageScreen, .commitTextEdit) }
              } else {
                Text(segment.text)
                  .textSelection(.enabled)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      .scrollIndicators(.visible)
    }
  }
}
