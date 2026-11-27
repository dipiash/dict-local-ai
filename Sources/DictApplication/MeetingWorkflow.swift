import DictCore
import Foundation

public protocol MeetingCapturing: AnyObject, Sendable {
  @MainActor var onSamples: @Sendable ([Float], TimeInterval) -> Void { get set }
  @MainActor var onFailure: @MainActor @Sendable (String) -> Void { get set }
  @MainActor var onSystemAudioDetected: @MainActor @Sendable () -> Void { get set }
  @MainActor func start() async throws
  @MainActor func stop() async
}

public protocol MeetingRecognizingPipeline: Sendable {
  @discardableResult func append(samples: [Float], at start: Double) -> Bool
  func finish(completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void)
  func cancel()
}

public protocol MeetingRecognizing: Sendable {
  func makeMeetingPipeline(
    onUpdate: @escaping @MainActor @Sendable ([TranscriptSegment], Double) -> Void,
    onFailure: @escaping @MainActor @Sendable (Error) -> Void,
    onFinalize: @escaping @MainActor @Sendable ([TranscriptSegment], DiarizationAudit) -> Void
  ) async throws -> any MeetingRecognizingPipeline
}

public struct SavedMeeting: Identifiable, Sendable {
  public let id: UUID
  public let transcript: FileTranscript
  public let date: Date

  public init(id: UUID, transcript: FileTranscript, date: Date) {
    self.id = id
    self.transcript = transcript
    self.date = date
  }
}

public protocol MeetingJournalPort: AnyObject {
  var onError: @MainActor @Sendable (Error) -> Void { get set }
  func begin(_ transcript: FileTranscript) -> UUID
  func resumeRecord(_ id: UUID, with transcript: FileTranscript)
  func append(_ segments: [TranscriptSegment], until: Double)
  func replaceSegments(_ segments: [TranscriptSegment])
  func finish(duration: Double, complete: Bool)
  func flush()
  func read(_ id: UUID) throws -> FileTranscript?
  func save(_ transcript: FileTranscript, to id: UUID?) throws -> UUID
  func delete(_ id: UUID) throws
  func deleteAll() throws
}

@MainActor
public final class MeetingWorkflow {
  public enum State { case idle, preparing, recording, finishing }
  public enum StopReason {
    case requested, setupCancelled
    case capture(String)
    case recognition(Error)
    public var isComplete: Bool {
      if case .requested = self { return true }
      return false
    }
  }

  private let modes: ModeCoordinator
  private let journal: any MeetingJournalPort
  private var lease: ModeCoordinator.Lease?
  private var journalActive = false
  private var autosaveRecordID: UUID?

  public init(modes: ModeCoordinator, journal: any MeetingJournalPort) {
    self.modes = modes
    self.journal = journal
  }

  public func begin(state: State, ready: () -> Bool) -> Bool {
    guard state == .idle, ready(), let acquired = modes.acquire(.meeting) else { return false }
    lease = acquired
    autosaveRecordID = nil
    return true
  }

  public func stop(state: State, reason: StopReason) -> StopReason? {
    guard state == .preparing || state == .recording else { return nil }
    if case .requested = reason, state == .preparing { return .setupCancelled }
    return reason
  }

  public func resolve(_ reason: StopReason, result: Result<Void, Error>) -> StopReason {
    guard reason.isComplete, case .failure(let error) = result else { return reason }
    return .recognition(error)
  }

  public func makeTranscript(title: String, startedAt: Date) -> FileTranscript {
    var document = FileTranscript(source: title, duration: 0)
    document.startedAt = startedAt
    document.speakerRecognitionEnabled = true
    document.diarizationMethod = "nemotron3-fast32"
    return document
  }

  public func setAutosave(
    _ enabled: Bool, state: State, elapsed: Int, transcript: FileTranscript?,
    onError: @escaping @MainActor @Sendable (Error) -> Void
  ) -> UUID? {
    if !enabled {
      closeJournal(duration: Double(elapsed), complete: false)
      return nil
    }
    guard !journalActive, state == .recording, let transcript else { return nil }
    // Resume the existing History record so the same audio file has a single owner.
    guard let id = autosaveRecordID else {
      return beginAutosave(transcript, enabled: enabled, onError: onError)
    }
    journal.onError = onError
    journal.resumeRecord(id, with: transcript)
    journalActive = true
    return id
  }

  public func beginAutosave(
    _ document: FileTranscript, enabled: Bool,
    onError: @escaping @MainActor @Sendable (Error) -> Void
  ) -> UUID? {
    guard enabled, !journalActive else { return nil }
    journal.onError = onError
    journalActive = true
    let id = journal.begin(document)
    autosaveRecordID = id
    return id
  }

  public func append(
    _ segments: [TranscriptSegment], until: Double, elapsed: Int,
    to transcript: inout FileTranscript?
  ) {
    transcript?.segments.append(contentsOf: segments)
    if let processedUntil = transcript?.processedUntil {
      transcript?.processedUntil = max(processedUntil, until)
    }
    transcript?.duration = max(Double(elapsed), until)
    if journalActive { journal.append(segments, until: until) }
  }

  public func replaceSegments(_ segments: [TranscriptSegment], in transcript: inout FileTranscript?)
  {
    transcript?.segments = segments
    if journalActive { journal.replaceSegments(segments) }
  }

  public func finalize(
    _ transcript: inout FileTranscript?, elapsed: Int, reason: StopReason
  ) {
    let duration = max(Double(elapsed), transcript?.processedUntil ?? 0)
    transcript?.duration = duration
    transcript?.complete = reason.isComplete
    transcript?.segments.sort { $0.start < $1.start }
    transcript?.suggestNames()
    closeJournal(duration: transcript?.duration ?? 0, complete: reason.isComplete)
    journal.flush()
  }

  public func release() {
    modes.release(lease)
    lease = nil
  }

  public func read(_ id: UUID) throws -> FileTranscript? {
    try journal.read(id)
  }

  public func save(_ transcript: FileTranscript, to id: UUID?) throws -> UUID {
    try journal.save(transcript, to: id)
  }

  public func delete(_ id: UUID) throws {
    try journal.delete(id)
  }

  public func deleteAll() throws {
    try journal.deleteAll()
  }

  public func shutdown(elapsed: Int) {
    closeJournal(duration: Double(elapsed), complete: false)
    journal.flush()
  }

  private func closeJournal(duration: Double, complete: Bool) {
    guard journalActive else { return }
    journal.finish(duration: duration, complete: complete)
    journalActive = false
  }
}
