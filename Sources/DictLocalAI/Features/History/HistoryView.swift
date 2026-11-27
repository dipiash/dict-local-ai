import AppKit
import DictCore
import ServiceManagement
import SwiftUI

struct HistoryView: View {
  @ObservedObject var store: HistoryStore
  @ObservedObject var meeting: MeetingSession
  @State private var filter: Filter = .all
  @State private var deleteTarget: UUID?
  @State private var confirmClear = false
  @State private var notice = ""
  @State private var pendingChange: PendingHistoryChange?

  private enum PendingHistoryChange {
    case selection(UUID?)
    case filter(Filter)
    case delete(UUID?)
    case clear
  }

  private enum Filter: String, CaseIterable, Identifiable {
    case all
    case dictation
    case meeting
    case file
    var id: Self { self }

    var title: String {
      switch self {
      case .all: L10n.text("history.all")
      case .dictation: L10n.text("menu.dictation-label")
      case .meeting: L10n.text("menu.meetings-label")
      case .file: L10n.text("menu.files-label")
      }
    }

    var category: RecordingCategory? {
      switch self {
      case .all: nil
      case .dictation: .dictation
      case .meeting: .meeting
      case .file: .file
      }
    }
  }

  private var visible: [RecordingSummary] {
    store.entries.filter { filter.category == nil || $0.category == filter.category }
  }

  private var selected: RecordingSummary? {
    store.entries.first { $0.id == store.draftID }
  }

  private var currentMeetingIsSelected: Bool {
    meeting.running && meeting.selectedMeeting == store.draftID && store.draftID != nil
  }

  var body: some View {
    GeometryReader { viewport in
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
        HStack {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            WorkspaceHeader(
              title: L10n.text("menu.history-label"),
              subtitle: L10n.text("history.browse-saved-dictation-meetings-and"))
          }
          Spacer()
          Button {
            UsageTelemetry.action(.history, .refreshHistory)
            store.reload()
          } label: {
            Label(L10n.text("history.refresh"), systemImage: "arrow.clockwise")
          }
          .help(L10n.text("history.refresh-history"))
          Button(L10n.text("history.clear"), role: .destructive) {
            UsageTelemetry.action(.history, .clearHistoryPrompt)
            requestHistoryChange(.clear)
          }
          .disabled(visible.isEmpty || meeting.running)
        }
        // Changing toolbar height after selection moves the history list.
        ViewThatFits(in: .horizontal) {
          HStack(spacing: DesignTokens.Spacing.xs) {
            historyFilter
            Spacer(minLength: DesignTokens.Spacing.xs)
            historyPlaybackButton

            historyActionMenu
          }
          .fixedSize(horizontal: true, vertical: false)
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            historyFilter
            HStack {
              Spacer(minLength: 0)
              historyPlaybackButton
              historyActionMenu
            }

          }
        }
        .accessibilityIdentifier("history-filter-toolbar")

        if let error = store.error {
          Text(error).font(AppStyle.caption).foregroundStyle(.red)
        }
        if !notice.isEmpty {
          Text(notice).font(AppStyle.caption).foregroundStyle(.secondary)
        }

        if visible.isEmpty {
          VStack(spacing: DesignTokens.Spacing.s) {
            AppEmptyState(
              title: store.entries.isEmpty
                ? L10n.text("history.no-records")
                : L10n.text("history.no-records-in-this-category"),
              symbol: "clock.arrow.circlepath",
              message: store.entries.isEmpty
                ? L10n.text("history.dictation-meetings-and-transcribed-files")
                : L10n.text("history.records-in-history-change-the", Int64(store.entries.count))
            )
            if !store.entries.isEmpty {
              Button(L10n.text("history.show-all-records")) { requestHistoryChange(.filter(.all)) }
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          HStack(spacing: DesignTokens.Spacing.none) {
            List(
              visible,
              selection: Binding<UUID?>(
                get: { store.draftID },
                set: { requestHistoryChange(.selection($0)) })
            ) { entry in
              VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                  Image(systemName: symbol(for: entry.category))
                    .foregroundStyle(.secondary)
                  Text(entry.title).lineLimit(1).font(.subheadline.weight(.medium))
                }
                Text(entry.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                  .font(AppStyle.caption).foregroundStyle(.secondary)
                Text(
                  L10n.text(
                    "history.record-summary", "\(FileTranscript.time(entry.duration))",
                    "\(entry.segmentCount)")
                )
                .font(AppStyle.caption).foregroundStyle(.tertiary)
                if !entry.preview.isEmpty {
                  Text(entry.preview)
                    .lineLimit(2)
                    .font(AppStyle.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .padding(.vertical, DesignTokens.Spacing.xxs)
              .tag(entry.id)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(
              DesignTokens.Colors.surface,
              in: RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
            )
            .clipShape(
              RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
            )
            .padding(DesignTokens.Spacing.xs)
            .frame(width: DesignTokens.Layout.historySidebarIdealWidth)
            .accessibilityIdentifier("history-entries-list")

            Divider()
              .padding(.vertical, DesignTokens.Spacing.xs)

            Group {
              if let document = store.draftDocument, let selected {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                  HStack {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                      Text(selected.title).font(AppStyle.section).lineLimit(2)
                      Text(
                        "\(label(for: selected.category)) · \(FileTranscript.time(document.duration))"
                      )
                      .font(AppStyle.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                  }
                  TranscriptResultView(
                    transcript: document, usageScreen: .history,
                    editable: selected.category != .dictation && !currentMeetingIsSelected,
                    rename: { id, name in
                      store.renameDraftSpeaker(id, name: name)
                    },
                    editText: selected.category == .dictation || currentMeetingIsSelected
                      ? nil
                      : {
                        index, text in
                        store.editDraftSegment(index, text: text)
                      }
                  )

                }
                .padding(DesignTokens.Spacing.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              } else {
                AppEmptyState(
                  title: L10n.text("history.select-a-record"), symbol: "text.alignleft",
                  message:
                    L10n.text("history.view-edit-copy-or-export")
                )
              }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .padding(AppStyle.pagePadding)
      .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      store.reload()
    }
    .onDisappear {
      store.audio.stop(reason: .viewClosed)
    }
    .onChange(of: store.draftID) { _, _ in store.audio.stop(reason: .switched) }
    .onReceive(NotificationCenter.default.publisher(for: .recordingStoreDidChange)) { _ in
      store.reload()
    }
    .confirmationDialog(
      L10n.text("history.unsaved-changes"),
      isPresented: Binding(
        get: { pendingChange != nil },
        set: { if !$0 { pendingChange = nil } })
    ) {
      Button(L10n.text("history.save-and-continue")) { resolveHistoryChange(save: true) }
      Button(L10n.text("history.continue-without-saving"), role: .destructive) {
        resolveHistoryChange(save: false)
      }
      Button(L10n.text("menu.cancel"), role: .cancel) { pendingChange = nil }
    } message: {
      Text(L10n.text("history.save-or-discard-your-transcript"))
    }
    .confirmationDialog(L10n.text("history.clear-history"), isPresented: $confirmClear) {
      Button(L10n.text("history.delete-records", "\(filter.title)"), role: .destructive) {
        UsageTelemetry.action(.history, .clearHistoryConfirm)
        store.clear(category: filter.category)
        store.discardDraft()
        store.selectDraft(nil)
      }
    } message: {
      Text(L10n.text("history.this-deletion-is-permanent-original"))
    }
    .alert(
      L10n.text("history.delete-this-record"),
      isPresented: Binding(
        get: { deleteTarget != nil },
        set: { if !$0 { deleteTarget = nil } }
      )
    ) {
      Button(L10n.text("menu.cancel"), role: .cancel) { deleteTarget = nil }
      Button(L10n.text("history.delete"), role: .destructive) {
        UsageTelemetry.action(.history, .deleteEntryConfirm)
        if let deleteTarget { store.delete(deleteTarget) }
        deleteTarget = nil
        store.discardDraft()
        store.selectDraft(nil)
      }
    } message: {
      Text(L10n.text("history.this-record-s-text-and"))
    }
  }

  private var historyFilter: some View {
    Picker(
      L10n.text("history.category"),
      selection: Binding(
        get: { filter },
        set: { proposed in requestHistoryChange(.filter(proposed)) })
    ) {
      ForEach(Filter.allCases) { option in
        Text(option.title).tag(option)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityLabel(L10n.text("history.history-filter"))
  }

  @ViewBuilder
  private var historyPlaybackButton: some View {
    if let document = store.draftDocument, let id = store.draftID, selected != nil,
      store.audio.fileURL(audioFile: document.audioFile) != nil
    {
      let playing = store.audio.isPlaying(id)
      let title = playing ? L10n.text("history.stop") : L10n.text("history.listen")
      Button {
        toggleHistoryPlayback(id: id, audioFile: document.audioFile)
      } label: {
        Label(title, systemImage: playing ? "stop.fill" : "play.fill")
      }
      .accessibilityIdentifier("history-listen")
      .help(title)
      .fixedSize()
    }
  }

  private var historyActionMenu: some View {
    Menu(L10n.text("history.record-actions")) {
      if let document = store.draftDocument, selected != nil {
        Button(L10n.text("menu.copy")) {
          UsageTelemetry.action(.history, .copyTranscript)
          TextInsertion.copy(document.plainText)
        }
        Button("TXT…") { export(document, format: "txt") }
        Button("JSON…") { export(document, format: "json") }
        if store.draftDirty {
          Button(L10n.text("menu.save")) { _ = store.saveDraft() }
            .disabled(currentMeetingIsSelected)
        }
        Button(L10n.text("history.delete"), role: .destructive) {
          requestHistoryChange(.delete(store.draftID))
        }
        .disabled(currentMeetingIsSelected)
      }
    }
    .disabled(store.draftDocument == nil || selected == nil)
    .accessibilityIdentifier("history-record-actions")
  }

  private func requestHistoryChange(_ change: PendingHistoryChange) {
    if UnsavedEditPolicy.requiresConfirmation(dirty: store.draftDirty, changesContext: true) {
      pendingChange = change
      DiagnosticLog.shared.event("history-ui", "unsaved_change_prompted")
    } else {
      applyHistoryChange(change)
    }
  }

  private func applyHistoryChange(_ change: PendingHistoryChange) {
    switch change {
    case .selection(let id):
      UsageTelemetry.action(.history, .selectEntry)
      store.selectDraft(id)
    case .filter(let next):
      filter = next
      store.selectDraft(nil)
      DiagnosticLog.shared.event(
        "history-ui", "filter_changed", "category=\(next.category?.rawValue ?? "all")")
    case .delete(let id):
      deleteTarget = id
    case .clear:
      confirmClear = true
    }
  }

  private func resolveHistoryChange(save: Bool) {
    guard let pendingChange else { return }
    if save {
      guard store.saveDraft() else { return }
    } else {
      store.discardDraft()
    }
    self.pendingChange = nil
    applyHistoryChange(pendingChange)
  }

  private func toggleHistoryPlayback(id: UUID, audioFile: String?) {
    do { try store.audio.toggle(id: id, audioFile: audioFile) } catch {
      notice = L10n.text("history.could-not-play", L10n.error(error))
    }
  }

  private func export(_ transcript: FileTranscript, format: String) {
    let base = URL(fileURLWithPath: transcript.source).deletingPathExtension().lastPathComponent
    do {
      if let url = try TranscriptExporter.save(transcript, format: format, basename: base) {
        notice = L10n.text("dictation.saved", "\(url.lastPathComponent)")
      }
    } catch { notice = L10n.text("history.export-failed", L10n.error(error)) }
  }

  private func label(for category: RecordingCategory) -> String {
    switch category {
    case .dictation: L10n.text("menu.dictation-label")
    case .meeting: L10n.text("history.meeting")
    case .file: L10n.text("history.file")
    }
  }

  private func symbol(for category: RecordingCategory) -> String {
    switch category {
    case .dictation: "mic"
    case .meeting: "person.2.wave.2"
    case .file: "doc.text"
    }
  }
}
