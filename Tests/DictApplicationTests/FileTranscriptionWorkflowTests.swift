import DictApplication
import DictCore
import Foundation
import Synchronization
import XCTest

final class FileTranscriptionWorkflowTests: XCTestCase {
  @MainActor
  func testCancellationKeepsRecognizedPartialAndReleasesMode() async throws {
    let modes = ModeCoordinator()
    let writer = Writer()
    let workflow = FileTranscriptionWorkflow(modes: modes, writer: { writer })
    XCTAssertTrue(
      workflow.begin(ready: { true }, identifySpeakers: true, speakerModelsReady: { true }))
    XCTAssertNil(modes.acquire(.meeting))
    var transcript: FileTranscript? = workflow.makeTranscript(
      source: "Sample", duration: 10, identifySpeakers: true)
    let sample = TranscriptSegment(start: 0, end: 2, text: "Example")
    workflow.append(
      [sample], source: "Sample", duration: 10, until: 2, identifySpeakers: true, to: &transcript)

    let completion = workflow.finish(
      .failure(CancellationError()), transcript: &transcript, identifySpeakers: true)
    XCTAssertEqual(completion.diagnosticOutcome, "cancelled")
    XCTAssertFalse(completion.retryable)
    XCTAssertNil(modes.active)
    XCTAssertEqual(transcript?.segments, [sample])
    XCTAssertEqual(transcript?.complete, false)
    XCTAssertFalse(try workflow.saveIfEligible(transcript, enabled: false))
    XCTAssertTrue(try workflow.saveIfEligible(transcript, enabled: true))
    XCTAssertEqual(writer.recordings.withLock { $0.map(\.0) }, [.file])
    XCTAssertEqual(writer.recordings.withLock { $0.map(\.1) }, [transcript])
  }

  @MainActor
  func testDiarizationFailureKeepsCompleteSpeechAndAllowsRetry() async throws {
    let workflow = FileTranscriptionWorkflow(modes: ModeCoordinator(), writer: { Writer() })
    var transcript: FileTranscript? = workflow.makeTranscript(
      source: "Sample", duration: 10, identifySpeakers: true)
    workflow.append(
      [TranscriptSegment(start: 1, end: 10, text: "Example")], source: "Sample", duration: 10,
      until: 10, identifySpeakers: true, to: &transcript)
    let completion = workflow.finish(
      .failure(TestFailure()), transcript: &transcript, identifySpeakers: true)
    guard case .diarizationFailed = completion else {
      return XCTFail("Expected a diarization failure after speech recognition completed")
    }
    XCTAssertTrue(completion.retryable)
    XCTAssertEqual(transcript?.speakerRecognitionEnabled, false)
    XCTAssertEqual(transcript?.diarizationMethod, "diarization-failed")
    XCTAssertEqual(transcript?.segments.count, 1)
  }

  private struct TestFailure: Error {}

  private final class Writer: RecordingWriter {
    let recordings = Mutex<[(RecordingCategory, FileTranscript)]>([])

    func create(
      _ transcript: FileTranscript, category: RecordingCategory, id: UUID, date: Date
    ) throws -> UUID {
      recordings.withLock { $0.append((category, transcript)) }
      return id
    }
  }
}
