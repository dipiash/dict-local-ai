import Foundation

public enum DiarizationReviewConsensus {
  public enum Classification: String, Sendable {
    case potentialMissedChange = "potential_missed_change"
    case repeatedDisagreement = "repeated_disagreement"
    case existingSpeakerSplit = "existing_speaker_split"
  }

  public struct Candidate: Sendable {
    public let start: Double
    public let end: Double
    public let mainSpeaker: String
    public let windowCount: Int
    public let classification: Classification
  }

  public static func group(
    _ findings: [DiarizationDisagreement.Finding],
    minimumOverlapRatio: Double = 0.5
  ) -> [Candidate] {
    let sorted = findings.filter {
      $0.end > $0.start && $0.start.isFinite && $0.end.isFinite
    }.sorted { $0.start < $1.start }
    struct Cluster {
      var start: Double
      var end: Double
      var speaker: String
      var windowKeys: Set<String>
      var alreadySeparateSpeaker: Bool
    }
    var clusters: [Cluster] = []
    for item in sorted {
      let key = "\(item.windowStart)-\(item.windowEnd)"
      let len = item.end - item.start
      let index = clusters.indices.first { index in
        let cluster = clusters[index]
        guard cluster.speaker == item.mainSpeaker else { return false }
        let overlap = max(0, min(cluster.end, item.end) - max(cluster.start, item.start))
        return overlap >= minimumOverlapRatio * min(cluster.end - cluster.start, len)
      }
      if let index {
        clusters[index].start = min(clusters[index].start, item.start)
        clusters[index].end = max(clusters[index].end, item.end)
        clusters[index].windowKeys.insert(key)
        clusters[index].alreadySeparateSpeaker =
          clusters[index].alreadySeparateSpeaker && item.alreadySeparateSpeaker
      } else {
        clusters.append(
          .init(
            start: item.start, end: item.end, speaker: item.mainSpeaker,
            windowKeys: [key], alreadySeparateSpeaker: item.alreadySeparateSpeaker))
      }
    }
    return clusters.map {
      Candidate(
        start: $0.start, end: $0.end,
        mainSpeaker: $0.speaker, windowCount: $0.windowKeys.count,
        classification: $0.alreadySeparateSpeaker
          ? .existingSpeakerSplit
          : ($0.windowKeys.count >= 2 ? .repeatedDisagreement : .potentialMissedChange))
    }
  }
}
