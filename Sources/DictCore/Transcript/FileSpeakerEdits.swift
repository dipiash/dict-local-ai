public enum FileSpeakerEdits {
  public static func rename(_ id: String, name: String, in document: inout FileTranscript) -> Bool {
    guard document.speakerIDs.contains(id) else { return false }
    document.speakerNames[id] = name
    return true
  }

  public static func assign(_ speaker: String?, at index: Int, in document: inout FileTranscript)
    -> Bool
  {
    guard document.segments.indices.contains(index), document.speakerRecognitionEnabled != false
    else { return false }
    let segment = document.segments[index]
    document.segments[index] = TranscriptSegment(
      start: segment.start, end: segment.end, text: segment.text,
      speakerID: speaker, channel: segment.channel)
    return true
  }

  public static func nextID(in document: FileTranscript) -> String {
    let existing = Set(document.speakerIDs)
    return (1...max(2, existing.count + 2))
      .map { "S\($0)" }.first { !existing.contains($0) } ?? "S\(existing.count + 1)"
  }
}
