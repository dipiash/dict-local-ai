import DictCore
import Foundation
import SwiftUI

/// Decides when a slider change jumps the sound: on release after a drag, at once otherwise.
struct SeekCommitTracker {
  private(set) var dragging = false
  private var pending: Double?
  private var lastSeek: (value: Double, time: TimeInterval)?
  /// Treat an identical seek gesture during this interval as a duplicate.
  static let duplicateSeekInterval: TimeInterval = 0.4

  /// Return an immediate seek target when the slider value changes, if one is needed.
  mutating func valueChanged(_ value: Double, shown: Double) -> Double? {
    if dragging {
      pending = value
      return nil
    }
    // SwiftUI repeats the released value, and the shown time has moved on by then.
    if let lastSeek, abs(value - lastSeek.value) < 0.001 { return nil }
    guard value != shown else { return nil }
    lastSeek = (value, ProcessInfo.processInfo.systemUptime)
    return value
  }

  /// Track the drag and return the seek target when the mouse is released.
  mutating func editingChanged(
    _ editing: Bool, at now: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) -> Double? {
    dragging = editing
    guard !editing else { return nil }
    defer { pending = nil }
    guard let target = pending else { return nil }
    // SwiftUI replays press, same value, release right after a jump. A real press needs longer.
    if let lastSeek, abs(target - lastSeek.value) < 0.001,
      now - lastSeek.time < Self.duplicateSeekInterval
    {
      return nil
    }
    lastSeek = (target, now)
    return target
  }
}

/// Show playback progress and total duration in the History toolbar.
struct HistoryPlaybackSlider: View {
  @ObservedObject var player: HistoryPlaybackController
  let id: UUID
  /// Length of the record when no sound plays yet.
  let recordDuration: Double
  let compact: Bool
  let seek: (TimeInterval) -> Void
  @State private var previewPosition: Double?
  @State private var gate = SeekCommitTracker()

  private var playing: Bool { player.isPlaying(id) }
  private var total: Double { max(playing ? player.duration : recordDuration, 0.1) }
  private var shown: Double { min(previewPosition ?? (playing ? player.position : 0), total) }

  var body: some View {
    HStack(spacing: DesignTokens.Spacing.xs) {
      Slider(
        value: Binding(
          get: { shown },
          set: { value in
            if let target = gate.valueChanged(value, shown: shown) {
              seek(target)
            } else if gate.dragging {
              previewPosition = value
            }
          }),
        in: 0...total,
        onEditingChanged: { editing in
          // Apply the seek once the drag ends.
          let target = gate.editingChanged(editing)
          if !editing { previewPosition = nil }
          if let target { seek(target) }
        }
      )
      .accessibilityIdentifier("history-seek-slider")
      .frame(minWidth: compact ? 80 : 120, maxWidth: compact ? .infinity : 240)
      .accessibilityLabel(L10n.text("history.position"))
      Text("\(Self.clock(shown)) / \(Self.clock(total))")
        .font(AppStyle.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }
  }

  /// "12:34", or "1:02:03" for a record longer than an hour.
  static func clock(_ seconds: Double) -> String {
    let total = Int(max(0, seconds))
    return total >= 3600
      ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
      : String(format: "%02d:%02d", total / 60, total % 60)
  }
}
