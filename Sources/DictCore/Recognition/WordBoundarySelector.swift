import Foundation

public struct WordBoundarySelector: Sendable {
  private var committedUntil: Double?
  public init() {}

  public mutating func select(
    tokens: [RecognizedToken], start: Double, end: Double, hasRightContext: Bool
  ) -> (tokens: [RecognizedToken], start: Double, end: Double) {
    let lower = max(start, committedUntil ?? start)
    let upper: Double
    if hasRightContext,
      let nextWord = tokens.first(where: {
        $0.time >= end && $0.time <= end + 1.0 && $0.piece.first?.isWhitespace == true
      })
    {
      upper = nextWord.time
    } else {
      upper = end
    }
    let selected = tokens.filter { $0.time >= lower && $0.time < upper }
    committedUntil = upper
    return (selected, lower, upper)
  }
}
