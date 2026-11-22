import DictCore
import Foundation

extension FileTranscript {
  var plainText: String { plainText(using: L10n.format) }

  func plainText(using text: (String, [CVarArg]) -> String) -> String {
    let status =
      complete
      ? text("export.complete", [])
      : text("export.partial", [Self.time(processedUntil)])
    var header = [text("export.source", [source]), text("export.status", [status])]
    if let diarizationMethod {
      header.append(text("export.diarization-mode", [diarizationMethod]))
    }
    header += (asrWarnings ?? []).map { text("export.asr-warning", [$0]) }
    header.append(text("export.timestamp-note", []))
    let lines = segments.map { segment in
      let format = speakerRecognitionEnabled == nil ? Self.time : Self.segmentTime
      let time = "[\(format(segment.start))–\(format(segment.end))]"
      let channel =
        segment.channel.map {
          "[\(text($0 == "microphone" ? "settings.microphone" : "meeting.system-audio", []))] "
        } ?? ""
      let content =
        speakerRecognitionEnabled == false
        ? segment.text
        : "\(speakerTitle(segment.speakerID, using: text)): \(segment.text)"
      return "\(time) \(channel)\(content)"
    }
    return header.joined(separator: "\n") + "\n\n" + lines.joined(separator: "\n\n")
  }

  func speakerTitle(_ id: String?, using text: (String, [CVarArg]) -> String = L10n.format)
    -> String
  {
    guard let id else { return text("transcript.unknown-speaker", []) }
    if let name = speakerNames[id]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }
    if id.hasPrefix("mic-") {
      return text("transcript.microphone-speaker", [String(id.dropFirst(4))])
    }
    if id.hasPrefix("system-") {
      return text("transcript.system-speaker", [String(id.dropFirst(7))])
    }
    return text("transcript.speaker", [id])
  }
}
