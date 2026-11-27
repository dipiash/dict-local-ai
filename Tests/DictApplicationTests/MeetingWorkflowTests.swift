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
    let recordID = try XCTUnwrap(workflow.beginAutosave(document, enabled: true, onError: { _ in }))
    let provisional = TranscriptSegment(start: 0, end: 2, text: "First")
    workflow.append([provisional], until: 2, elapsed: 3, to: &transcript)
    XCTAssertNil(
      workflow.setAutosave(
        false, state: .recording, elapsed: 3, transcript: transcript, onError: { _ in }))
    XCTAssertNil(
      workflow.setAutosave(
        true, state: .finishing, elapsed: 3, transcript: transcript, onError: { _ in }))
    XCTAssertEqual(
      workflow.setAutosave(
        true, state: .recording, elapsed: 3, transcript: transcript, onError: { _ in }),
      recordID)
    XCTAssertEqual(journal.resumed, [recordID])
    let final = TranscriptSegment(start: 0, end: 2, text: "First", speakerID: "1")
    workflow.replaceSegments([final], in: &transcript)
    workflow.finalize(&transcript, elapsed: 4, reason: .requested)
    workflow.release()

    XCTAssertEqual(transcript?.segments, [final])
    XCTAssertEqual(transcript?.duration, 4)
    XCTAssertEqual(transcript?.complete, true)
    XCTAssertNil(modes.active)
    XCTAssertEqual(
      journal.events,
      [
        "begin", "append", "finish:3.0:false", "resume", "replace", "finish:4.0:true", "flush",
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

  @MainActor
  func testStoppingWithoutActiveMeetingFails() async {
    let workflow = MeetingWorkflow(modes: ModeCoordinator(), journal: Journal())
    XCTAssertNil(workflow.stop(state: .idle, reason: .capture("lost")))
    XCTAssertNil(workflow.stop(state: .finishing, reason: .requested))
  }

  private struct TestFailure: Error {}

  private final class Journal: MeetingJournalPort {
    var events = [String]()
    var resumed = [UUID]()
    var onError: @MainActor @Sendable (Error) -> Void = { _ in }

    func begin(_ transcript: FileTranscript) -> UUID {
      events.append("begin")
      return UUID()
    }

    func resumeRecord(_ id: UUID, with transcript: FileTranscript) {
      events.append("resume")
      resumed.append(id)
    }

    func append(_ segments: [TranscriptSegment], until: Double) { events.append("append") }
    func replaceSegments(_ segments: [TranscriptSegment]) { events.append("replace") }
    func finish(duration: Double, complete: Bool) {
      events.append("finish:\(duration):\(complete)")
    }
    func flush() { events.append("flush") }
    func read(_ id: UUID) throws -> FileTranscript? { nil }
    func save(_ transcript: FileTranscript, to id: UUID?) throws -> UUID { id ?? UUID() }
    func delete(_ id: UUID) throws {}
    func deleteAll() throws {}
  }
}
