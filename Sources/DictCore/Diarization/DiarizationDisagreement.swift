import Foundation

public enum DiarizationDisagreement {
  public struct Finding: Sendable {
    public let start: Double
    public let end: Double
    public let mainSpeaker: String
    public let dominantLocalSpeaker: String
    public let alternateLocalSpeaker: String
    public let dominantSupportSeconds: Double
    public let alternateSupportSeconds: Double
    public let windowStart: Double
    public let windowEnd: Double
    public var alreadySeparateSpeaker = false
  }

  public static func find(
    main: [SpeakerTurn], comparisons: [DiarizationAudit.ChunkRun],
    minimumSecondarySeconds: Double = 4,
    minimumSecondaryRatio: Double = 0.08,
    maximumMergeGap: Double = 2.5,
    minimumCandidateSpan: Double = 2
  ) -> [Finding] {
    var findings: [Finding] = []
    let full = main.filter(valid)
    for window in comparisons where window.end > window.start {
      let local = window.turns.filter(valid)
      var mainDurations: [String: Double] = [:]
      for turn in full {
        let seconds = max(0, min(turn.end, window.end) - max(turn.start, window.start))
        if seconds > 0 { mainDurations[turn.id, default: 0] += seconds }
      }
      let primaryMainSpeaker = mainDurations.sorted {
        $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
      }.first?.key
      var supports: [String: [String: Double]] = [:]
      for globalTurn in full where globalTurn.start < window.end && globalTurn.end > window.start {
        for localTurn in local
        where localTurn.start < globalTurn.end && localTurn.end > globalTurn.start {
          let seconds = overlap(globalTurn, localTurn)
          if seconds > 0 {
            supports[globalTurn.id, default: [:]][localTurn.id, default: 0] += seconds
          }
        }
      }
      for (globalID, localSupport) in supports {
        let ranked = localSupport.sorted { lhs, rhs in
          lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        guard let strongest = ranked.first, strongest.value > 0 else { continue }
        for alternate in ranked.dropFirst() {
          guard alternate.value >= minimumSecondarySeconds,
            alternate.value / strongest.value >= minimumSecondaryRatio
          else { continue }
          var pieces: [(start: Double, end: Double)] = []
          for globalTurn in full where globalTurn.id == globalID {
            for localTurn in local where localTurn.id == alternate.key {
              let start = max(globalTurn.start, localTurn.start)
              let end = min(globalTurn.end, localTurn.end)
              if end > start { pieces.append((start, end)) }
            }
          }
          pieces.sort { $0.start < $1.start }
          var merged: [(start: Double, end: Double)] = []
          for piece in pieces {
            if let index = merged.indices.last,
              piece.start - merged[index].end <= maximumMergeGap
            {
              merged[index].end = max(merged[index].end, piece.end)
            } else {
              merged.append(piece)
            }
          }
          for piece in merged where piece.end - piece.start >= minimumCandidateSpan {
            findings.append(
              Finding(
                start: piece.start, end: piece.end, mainSpeaker: globalID,
                dominantLocalSpeaker: strongest.key,
                alternateLocalSpeaker: alternate.key,
                dominantSupportSeconds: strongest.value,
                alternateSupportSeconds: alternate.value,
                windowStart: window.start, windowEnd: window.end,
                alreadySeparateSpeaker: globalID != primaryMainSpeaker))
          }
        }
      }
    }
    return findings.sorted {
      if $0.start == $1.start { return $0.windowEnd < $1.windowEnd }
      return $0.start < $1.start
    }
  }

  private static func valid(_ turn: SpeakerTurn) -> Bool {
    turn.start.isFinite && turn.end.isFinite && turn.end > turn.start
  }

  private static func overlap(_ a: SpeakerTurn, _ b: SpeakerTurn) -> Double {
    max(0, min(a.end, b.end) - max(a.start, b.start))
  }
}
