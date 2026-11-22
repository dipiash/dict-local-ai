import DictApplication
import Foundation
import Synchronization
import XCTest

@testable import DictCore

final class DictationCompletionTests: XCTestCase {
  private var transcript: FileTranscript {
    var document = FileTranscript(source: "Dictation", duration: 0)
    document.segments = [
      TranscriptSegment(start: 0, end: 1, text: "First."),
      TranscriptSegment(start: 1, end: 2, text: "Second."),
    ]
    return document
  }

  @MainActor
  func testCompletionSavesBeforePasteAndDoesNotRetryUnconfirmedDelivery() async throws {
    let completion = try XCTUnwrap(DictationCompletion(transcript: transcript, duration: 3))
    let writer = TestRecordingWriter()
    let workflow = DictationWorkflow(modes: ModeCoordinator(), writer: { writer })
    let (delivery, history) = workflow.finish(
      completion, saveHistory: true,
      insert: { text in
        let record = writer.saved.withLock { $0 }
        XCTAssertEqual(record?.duration, 3)
        XCTAssertEqual(record?.complete, true)
        XCTAssertEqual(text, "First. Second.")
        return .pasteRequested
      },
      insertInEditor: { _ in
        XCTFail("Unexpected editor insertion")
        return false
      },
      copy: { _ in
        XCTFail("Unexpected clipboard fallback")
        return false
      })
    XCTAssertEqual(delivery, .pasteRequested)
    guard case .success? = history else { return XCTFail("Expected history save") }
  }

  @MainActor
  func testUnavailableTargetFallsBackToEditorThenClipboard() async throws {
    let completion = try XCTUnwrap(DictationCompletion(transcript: transcript, duration: 3))
    let workflow = DictationWorkflow(
      modes: ModeCoordinator(), writer: { throw CancellationError() })
    XCTAssertEqual(
      workflow.finish(
        completion, saveHistory: false,
        insert: { _ in .unavailable }, insertInEditor: { _ in true },
        copy: { _ in
          XCTFail("Unexpected clipboard fallback")
          return false
        }
      ).delivery,
      .inserted)
    XCTAssertEqual(
      workflow.finish(
        completion, saveHistory: false,
        insertInEditor: { _ in false },
        copy: { $0 == "First. Second." }
      ).delivery,
      .copied)
    XCTAssertEqual(
      workflow.finish(completion, saveHistory: false, copy: { _ in false }).delivery,
      .retained)
  }

  @MainActor
  func testHistoryFailureStillDeliversTheResult() async throws {
    let completion = try XCTUnwrap(DictationCompletion(transcript: transcript, duration: 3))
    let workflow = DictationWorkflow(
      modes: ModeCoordinator(), writer: { throw CancellationError() })
    let (delivery, history) = workflow.finish(
      completion, saveHistory: true, copy: { $0 == "First. Second." })
    XCTAssertEqual(delivery, .copied)
    guard case .failure? = history else { return XCTFail("Expected history failure") }
  }

  func testMissingOrEmptyTranscriptHasNoResultToDeliver() {
    XCTAssertNil(DictationCompletion(transcript: nil, duration: 1))
    XCTAssertNil(
      DictationCompletion(transcript: FileTranscript(source: "Empty", duration: 0), duration: 1))
  }
}

private final class TestRecordingWriter: RecordingWriter {
  let saved = Mutex<FileTranscript?>(nil)

  func create(
    _ transcript: FileTranscript, category: RecordingCategory, id: UUID, date: Date
  ) throws -> UUID {
    XCTAssertEqual(category, .dictation)
    saved.withLock { $0 = transcript }
    return id
  }
}
