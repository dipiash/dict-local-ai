import Foundation

public struct OfflineTranscriptAligner: Sendable {
  public struct Settings: Sendable {
    public var maxWordsPerSegment = 95
    public var sentenceBreakAfterWords = 36
    public var silenceBreakSeconds = 2.0
    public var boundaryToleranceSeconds = 0.12
    // Retain speaker slots so names assigned during a meeting stay attached.
    public var renumberSpeakers = true
    public init() {}
  }

  private struct Word {
    var text: String
    let start: Double
    var end: Double
    var speaker: String?
    var confidence: Double = 0
    var supportSeconds: Double = 0
    var rawSpeaker: String?
    var reason: String = "asr_only"
  }

  public struct Result: Sendable {
    public let segments: [TranscriptSegment]
    public let words: [DiarizationAudit.Word]
  }

  public let settings: Settings
  public init(settings: Settings = .init()) { self.settings = settings }

  public func align(
    tokens: [RecognizedToken], turns: [SpeakerTurn], duration: Double,
    useSpeakers: Bool = true
  ) -> [TranscriptSegment] {
    detailedAlignment(
      tokens: tokens, turns: turns, duration: duration,
      useSpeakers: useSpeakers
    ).segments
  }

  public func detailedAlignment(
    tokens: [RecognizedToken], turns: [SpeakerTurn], duration: Double,
    useSpeakers: Bool = true
  ) -> Result {
    guard duration.isFinite, duration >= 0 else { return Result(segments: [], words: []) }
    var words = makeWords(tokens: tokens, duration: duration)
    guard !words.isEmpty else { return Result(segments: [], words: []) }

    if useSpeakers {
      let timeline = consolidatedTurns(turns, duration: duration)
      var nextTurn = 0
      var active: [SpeakerTurn] = []
      for index in words.indices {
        let from = max(0, words[index].start - settings.boundaryToleranceSeconds)
        let to = max(from + 0.12, words[index].end + settings.boundaryToleranceSeconds)
        while nextTurn < timeline.count && timeline[nextTurn].start < to {
          active.append(timeline[nextTurn])
          nextTurn += 1
        }
        active.removeAll { $0.end <= from }
        let decision = bestSpeaker(for: words[index], in: active)
        words[index].speaker = decision.speaker
        words[index].rawSpeaker = decision.speaker
        words[index].confidence = decision.confidence
        words[index].supportSeconds = decision.support
        words[index].reason = decision.reason
      }
      stabilize(&words)
    }

    var speakerNumbers: [String: String] = [:]
    var segments: [TranscriptSegment] = []
    var groupStart = 0

    func flush(until exclusive: Int) {
      guard exclusive > groupStart else { return }
      let slice = words[groupStart..<exclusive]
      let text = TranscriptCleanup.apply(slice.map(\.text).joined())
      guard !text.isEmpty else { return }
      let rawID = words[groupStart].speaker
      let id: String?
      if let rawID, !settings.renumberSpeakers {
        id = rawID
      } else if let rawID {
        if speakerNumbers[rawID] == nil {
          speakerNumbers[rawID] = String(speakerNumbers.count + 1)
        }
        id = speakerNumbers[rawID]
      } else {
        id = nil
      }
      segments.append(
        .init(
          start: words[groupStart].start,
          end: max(words[groupStart].start, words[exclusive - 1].end),
          text: text, speakerID: id))
    }

    for index in 1..<words.count {
      let previous = words[index - 1]
      let current = words[index]
      let count = index - groupStart
      let breakAtSentence =
        count >= settings.sentenceBreakAfterWords
        && previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
          .last.map { ".!?".contains($0) } == true
      let boundary =
        previous.speaker != current.speaker
        || current.start - previous.end > settings.silenceBreakSeconds
        || count >= settings.maxWordsPerSegment
        || breakAtSentence
      if boundary {
        flush(until: index)
        groupStart = index
      }
    }
    flush(until: words.count)
    return Result(
      segments: segments,
      words: words.map {
        DiarizationAudit.Word(
          text: $0.text, start: $0.start, end: $0.end,
          rawSpeaker: $0.rawSpeaker, assignedSpeaker: $0.speaker,
          supportSeconds: $0.supportSeconds, confidence: $0.confidence,
          reason: $0.reason)
      })
  }

  private func makeWords(tokens: [RecognizedToken], duration: Double) -> [Word] {
    var result: [Word] = []
    for token in tokens {
      guard token.time.isFinite, !token.piece.isEmpty else { continue }
      let time = min(duration, max(0, token.time))
      let isNew = result.isEmpty || token.piece.first?.isWhitespace == true
      if isNew {
        result.append(Word(text: token.piece, start: time, end: time, speaker: nil))
      } else {
        result[result.count - 1].text += token.piece
      }
    }
    for index in result.indices {
      // The model reports word starts, so keep inferred endings short.
      let nextStart = index + 1 < result.count ? result[index + 1].start : duration
      result[index].end = max(
        result[index].start,
        min(duration, result[index].start + 0.55, nextStart))
    }
    return result
  }

  private func consolidatedTurns(_ turns: [SpeakerTurn], duration: Double) -> [SpeakerTurn] {
    let cleaned = turns.compactMap { turn -> SpeakerTurn? in
      guard !turn.id.isEmpty, turn.start.isFinite, turn.end.isFinite else { return nil }
      let start = max(0, min(duration, turn.start))
      let end = max(0, min(duration, turn.end))
      guard end > start else { return nil }
      return .init(id: turn.id, start: start, end: end)
    }.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
    var result: [SpeakerTurn] = []
    for turn in cleaned {
      if let previous = result.last, previous.id == turn.id,
        turn.start <= previous.end + 0.15
      {
        result[result.count - 1] = .init(
          id: previous.id, start: previous.start, end: max(previous.end, turn.end))
      } else {
        result.append(turn)
      }
    }
    return result
  }

  private struct Decision {
    var speaker: String?
    var confidence: Double
    var support: Double
    var reason: String
  }

  private func bestSpeaker(for word: Word, in timeline: [SpeakerTurn]) -> Decision {
    let from = max(0, word.start - settings.boundaryToleranceSeconds)
    let to = max(from + 0.12, word.end + settings.boundaryToleranceSeconds)
    var support: [String: Double] = [:]
    for turn in timeline where turn.end > from && turn.start < to {
      support[turn.id, default: 0] += max(0, min(turn.end, to) - max(turn.start, from))
    }
    guard !support.isEmpty else {
      return Decision(speaker: nil, confidence: 0, support: 0, reason: "no_turn")
    }
    let ranked = support.sorted { $0.value > $1.value }
    guard let winner = ranked.first else {
      return Decision(speaker: nil, confidence: 0, support: 0, reason: "no_turn")
    }
    let total = ranked.reduce(0) { $0 + $1.value }
    let confidence = winner.value / max(total, 0.001)
    guard winner.value >= 0.12 else {
      return Decision(
        speaker: nil, confidence: confidence,
        support: winner.value, reason: "low_support")
    }
    guard confidence >= 0.65 else {
      return Decision(
        speaker: nil, confidence: confidence,
        support: winner.value, reason: "ambiguous_overlap")
    }
    return Decision(
      speaker: winner.key, confidence: confidence,
      support: winner.value, reason: "matched")
  }

  private func stabilize(_ words: inout [Word]) {
    guard words.count > 2 else { return }
    for index in 1..<(words.count - 1) {
      let previous = words[index - 1]
      let next = words[index + 1]
      guard previous.speaker != nil, previous.speaker == next.speaker,
        next.start - previous.end < 1.5
      else { continue }
      if words[index].speaker == nil || words[index].confidence < 0.6 {
        words[index].speaker = previous.speaker
        words[index].reason = "bridged_same_speaker"
      }
    }
    for index in words.indices where words[index].speaker == nil {
      let left = index > 0 ? words[index - 1] : nil
      let right = index + 1 < words.count ? words[index + 1] : nil
      if let left, left.speaker != nil, left.confidence >= 0.9,
        words[index].start - left.end < 0.25,
        right?.speaker == nil || right?.speaker == left.speaker
      {
        words[index].speaker = left.speaker
        words[index].reason = "attached_to_neighbor"
      }
    }
  }
}
