import DictApplication
import DictCore
import Foundation
import XCTest

final class MeetingWorkflowTests: XCTestCase {
  @MainActor
  func testAutosaveToggleAndFinalizationPreserveJournalOrder() async throws {
    let modes = ModeCoordinator()
    let journal = Journal()
    let workflow = MeetingWorkflow(modes: modes, journal: journal)
    XCTAssertTrue(workflow.begin(state: .idle, ready: { true }))
    XCTAssertNil(modes.acquire(.file))
    let started = Date(timeIntervalSince1970: 5)
    let document = workflow.makeTranscript(title: "Meeting", startedAt: started)
    XCTAssertEqual(document.startedAt, started)
    var transcript: FileTranscript? = document
    XCTAssertNotNil(workflow.beginAutosave(document, enabled: true, onError: { _ in }))
    let provisional = TranscriptSegment(start: 0, end: 2, text: "First")
    workflow.append([provisional], until: 2, elapsed: 3, to: &transcript)
    XCTAssertNil(
      workflow.setAutosave(
        false, state: .recording, elapsed: 3, transcript: transcript, onError: { _ in }))
    XCTAssertNil(
      workflow.setAutosave(
        true, state: .finishing, elapsed: 3, transcript: transcript, onError: { _ in }))
    XCTAssertNotNil(
      workflow.setAutosave(
        true, state: .recording, elapsed: 3, transcript: transcript, onError: { _ in }))
    let final = TranscriptSegment(start: 0, end: 2, text: "First", speakerID: "1")
    workflow.replaceSegments([final], in: &transcript)
    workflow.finalize(&transcript, elapsed: 4, reason: .requested)
    _ = try workflow.saved(now: started)
    workflow.release()

    XCTAssertEqual(transcript?.segments, [final])
    XCTAssertEqual(transcript?.duration, 4)
    XCTAssertEqual(transcript?.complete, true)
    XCTAssertNil(modes.active)
    XCTAssertEqual(
      journal.events,
      [
        "begin", "append", "finish:3.0:false", "begin", "replace", "finish:4.0:true", "flush",
        "saved:7",
      ])
  }

  @MainActor
  func testExistingStopReasonTakesPrecedenceOverPipelineFailure() async throws {
    let workflow = MeetingWorkflow(modes: ModeCoordinator(), journal: Journal())
    let preparing = try XCTUnwrap(workflow.stop(state: .preparing, reason: .requested))
    guard case .setupCancelled = workflow.resolve(preparing, result: .failure(TestFailure()))
    else { return XCTFail("Expected the setup cancellation reason") }
    guard case .recognition = workflow.resolve(.requested, result: .failure(TestFailure()))
    else { return XCTFail("Expected the pipeline failure reason") }
  }

  private struct TestFailure: Error {}

  private final class Journal: MeetingJournalPort {
    var events = [String]()
    var onError: @MainActor @Sendable (Error) -> Void = { _ in }

    func begin(_ transcript: FileTranscript) -> UUID {
      events.append("begin")
      return UUID()
    }

    func append(_ segments: [TranscriptSegment], until: Double) { events.append("append") }
    func replaceSegments(_ segments: [TranscriptSegment]) { events.append("replace") }
    func finish(duration: Double, complete: Bool) {
      events.append("finish:\(duration):\(complete)")
    }
    func flush() { events.append("flush") }
    func saved(retentionDays: Int, now: Date) throws -> [SavedMeeting] {
      events.append("saved:\(retentionDays)")
      return []
    }
    func read(_ id: UUID) throws -> FileTranscript? { nil }
    func save(_ transcript: FileTranscript, to id: UUID?) throws -> UUID { id ?? UUID() }
    func delete(_ id: UUID) throws {}
    func deleteAll() throws {}
  }
}
