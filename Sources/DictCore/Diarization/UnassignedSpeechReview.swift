import Foundation

public enum UnassignedSpeechReview {
  public struct Span: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let words: Int
  }

  public static func find(
    words: [DiarizationAudit.Word], maxGapSeconds: Double = 2.5,
    minimumWords: Int = 3, minimumDuration: Double = 1.5
  ) -> [Span] {
    let items = words.filter {
      $0.assignedSpeaker == nil && $0.start.isFinite && $0.end.isFinite
        && $0.end >= $0.start
    }.sorted { $0.start < $1.start }
    guard !items.isEmpty else { return [] }
    var start = items[0].start
    var end = items[0].end
    var count = 0
    var spans: [Span] = []
    func emit() {
      if count >= minimumWords && end - start >= minimumDuration {
        spans.append(Span(start: start, end: end, words: count))
      }
    }
    for word in items {
      if word.start - end > maxGapSeconds {
        emit()
        start = word.start
        end = word.end
        count = 0
      }
      end = max(end, word.end)
      count += 1
    }
    emit()
    return spans
  }
}
