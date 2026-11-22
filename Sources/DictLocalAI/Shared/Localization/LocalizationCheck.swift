import DictCore
import Foundation

enum LocalizationCheck {
  static func printResult() {
    let bundle = Bundle.main
    var fixture = FileTranscript(source: "sample.wav", duration: 2)
    fixture.segments = [
      TranscriptSegment(start: 0, end: 2, text: "Тест Test", speakerID: "1")
    ]
    let result = [
      "export": fixture.plainText,
      "dictationTitle": L10n.text("menu.dictation-label"),
      "meetingTitle": L10n.text("meeting.recording-title", "10:30"),
      "available": bundle.localizations.sorted().joined(separator: ","),
      "preferred": bundle.preferredLocalizations.first ?? "",
      "development": bundle.developmentLocalization ?? "",
      "files": L10n.text("menu.files-label"),
      "progress": L10n.text("files.processed-time", "00:01", "00:02"),
      "one": L10n.text("files.updated-segments-in-this-episode", Int64(1)),
      "few": L10n.text("files.updated-segments-in-this-episode", Int64(2)),
      "many": L10n.text("files.updated-segments-in-this-episode", Int64(5)),
      "microphone": bundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        ?? "",
      "systemAudio": bundle.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription")
        as? String
        ?? "",
    ]
    do {
      let data = try JSONEncoder().encode(result)
      print(String(decoding: data, as: UTF8.self))
    } catch {
      FileHandle.standardError.write(Data("Could not encode localization check.\n".utf8))
    }
  }
}
