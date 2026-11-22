import AppKit
import DictCore
import UniformTypeIdentifiers

@MainActor
enum TranscriptExporter {
  static func savePlainText(_ text: String, basename: String) throws -> URL? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = basename + ".txt"
    panel.allowedContentTypes = [.plainText]
    guard panel.runModal() == .OK, let url = panel.url else {
      DiagnosticLog.shared.event("export", "cancelled", "format=txt mode=plain")
      return nil
    }
    do {
      let data = plainTextData(text)
      try data.write(to: url, options: .atomic)
      DiagnosticLog.shared.event("export", "completed", "format=txt mode=plain bytes=\(data.count)")
      return url
    } catch {
      DiagnosticLog.shared.event(
        "export", "failed", "format=txt mode=plain error_type=\(type(of: error))")
      throw error
    }
  }

  static func plainTextData(_ text: String) -> Data { Data(text.utf8) }

  static func save(_ transcript: FileTranscript, format: String, basename: String) throws -> URL? {
    guard format == "txt" || format == "json" else {
      throw AppFailure("export.supported-formats-txt-and-json")
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = basename + (transcript.complete ? "" : "-partial") + "." + format
    panel.allowedContentTypes = [UTType(filenameExtension: format) ?? .plainText]
    guard panel.runModal() == .OK, let url = panel.url else {
      DiagnosticLog.shared.event("export", "cancelled", "format=\(format)")
      return nil
    }
    do {
      let data = try format == "json" ? transcript.json() : Data(transcript.plainText.utf8)
      try data.write(to: url, options: .atomic)
      DiagnosticLog.shared.event(
        "export", "completed",
        "format=\(format) bytes=\(data.count) segments=\(transcript.segments.count)")
      return url
    } catch {
      DiagnosticLog.shared.event(
        "export", "failed", "format=\(format) error_type=\(type(of: error))")
      throw error
    }
  }
}
