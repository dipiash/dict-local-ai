import Foundation

public enum DiarizationSplitReview {
  public struct Candidate: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let transition: Double
    public let beforeSpeaker: String
    public let afterSpeaker: String
    public let supportingWindows: Int
  }

  public static func find(
    main: [SpeakerTurn], comparisons: [DiarizationAudit.ChunkRun],
    minimumIndependentWindows: Int = 2, contextSeconds: Double = 6,
    minimumSupportSeconds: Double = 0.9
  ) -> [Candidate] {
    let sorted = main.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
      .sorted { $0.start < $1.start }
    guard sorted.count >= 2 else { return [] }
    var candidates: [Candidate] = []
    for i in 1..<sorted.count {
      let before = sorted[i - 1]
      let after = sorted[i]
      guard before.id != after.id, after.start - before.end <= 2.5,
        after.start >= before.start, after.end > after.start
      else { continue }
      let boundary = (before.end + after.start) / 2
      let leftStart = max(before.start, boundary - contextSeconds)
      let rightEnd = min(after.end, boundary + contextSeconds)
      guard boundary - leftStart >= minimumSupportSeconds,
        rightEnd - boundary >= minimumSupportSeconds
      else { continue }
      var keys: Set<String> = []
      for replay in comparisons {
        guard replay.start <= leftStart, replay.end >= rightEnd else { continue }
        var bySpeaker: [String: (Double, Double)] = [:]
        for turn in replay.turns where turn.start < rightEnd && turn.end > leftStart {
          let left = max(0, min(turn.end, boundary) - max(turn.start, leftStart))
          let right = max(0, min(turn.end, rightEnd) - max(turn.start, boundary))
          var pair = bySpeaker[turn.id] ?? (0, 0)
          pair.0 += left
          pair.1 += right
          bySpeaker[turn.id] = pair
        }
        let leftTotal = bySpeaker.values.reduce(0) { $0 + $1.0 }
        let rightTotal = bySpeaker.values.reduce(0) { $0 + $1.1 }
        guard leftTotal >= minimumSupportSeconds, rightTotal >= minimumSupportSeconds else {
          continue
        }
        if bySpeaker.values.contains(where: {
          $0.0 >= minimumSupportSeconds && $0.1 >= minimumSupportSeconds
            && $0.0 / leftTotal >= 0.75 && $0.1 / rightTotal >= 0.75
        }) {
          keys.insert("\(replay.start):\(replay.end)")
        }
      }
      if keys.count >= minimumIndependentWindows {
        var episodeEnd = after.end
        for next in sorted[(i + 1)...] {
          if next.start > episodeEnd + 3 { break }
          if next.id == after.id && next.start <= episodeEnd + 3 {
            episodeEnd = max(episodeEnd, next.end)
          }
        }
        candidates.append(
          .init(
            start: before.start, end: episodeEnd, transition: boundary,
            beforeSpeaker: before.id, afterSpeaker: after.id,
            supportingWindows: keys.count))
      }
    }
    return candidates
  }
}

public enum SpeakerReviewEdits {
  public static func mergeEpisode(
    _ segments: [TranscriptSegment], candidate: DiarizationSplitReview.Candidate
  ) -> (segments: [TranscriptSegment], changed: Int) {
    var changed = 0
    let result = segments.map { segment -> TranscriptSegment in
      guard segment.speakerID == candidate.afterSpeaker,
        segment.start >= candidate.transition - 0.05,
        segment.end <= candidate.end + 0.05
      else { return segment }
      changed += 1
      return TranscriptSegment(
        start: segment.start, end: segment.end, text: segment.text,
        speakerID: candidate.beforeSpeaker, channel: segment.channel)
    }
    return (result, changed)
  }
}
