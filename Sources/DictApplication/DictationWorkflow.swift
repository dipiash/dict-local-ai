import DictCore
import Foundation

@MainActor
public struct DictationWorkflow {
  public static let maximumSeconds = 1800
  private let modes: ModeCoordinator
  private let writer: @Sendable () throws -> any RecordingWriter

  public init(modes: ModeCoordinator, writer: @escaping @Sendable () throws -> any RecordingWriter)
  {
    self.modes = modes
    self.writer = writer
  }

  public func start(enabled: Bool, phase: DictationPhase) -> ModeCoordinator.Lease? {
    guard enabled, phase.canStart else { return nil }
    return modes.acquire(.dictation)
  }

  public func canRetry(phase: DictationPhase) -> Bool {
    phase == .failed || phase == .interrupted
  }

  public func retry() -> ModeCoordinator.Lease? { modes.acquire(.dictation) }

  public func release(_ lease: ModeCoordinator.Lease?) { modes.release(lease) }

  public func shouldFinish(elapsed: Int, sampleCount: Int) -> Bool {
    elapsed >= Self.maximumSeconds || sampleCount >= AudioWindow.maximumSamples
  }

  public func finish(
    _ completion: DictationCompletion,
    saveHistory: Bool,
    insert: (String) -> TextInsertionOutcome = { _ in .unavailable },
    insertInEditor: (String) -> Bool = { _ in false },
    copy: (String) -> Bool
  ) -> (delivery: DictationCompletion.Delivery, history: Result<Void, Error>?) {
    let history: Result<Void, Error>? =
      saveHistory
      ? Result {
        let transcript = completion.transcript
        _ = try writer().create(
          transcript, category: .dictation, id: UUID(), date: transcript.startedAt ?? Date())
      } : nil
    let text = completion.text
    switch insert(text) {
    case .inserted: return (.inserted, history)
    case .pasteRequested: return (.pasteRequested, history)
    case .unavailable:
      if insertInEditor(text) { return (.inserted, history) }
      return (copy(text) ? .copied : .retained, history)
    }
  }
}

public protocol DictationCapturing: Sendable {
  var count: Int { get }
  var level: Float { get }
  func copy(from start: Int) -> [Float]
  func erase()
  func start(deviceID: String, requestID: UUID) async throws
  func stop(requestID: UUID, discard: Bool) async
}

public protocol DictationRecognizingPipeline: Sendable {
  @discardableResult func append(samples: [Float], at start: Double) -> Bool
  func finish(completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void)
  func cancel()
  func waitForDrain() async
}

public protocol DictationRecognizing: Sendable {
  func makeDictationPipeline(
    onUpdate: @escaping @MainActor @Sendable ([TranscriptSegment], Double) -> Void,
    onFailure: @escaping @MainActor @Sendable (Error) -> Void
  ) async throws -> any DictationRecognizingPipeline
}
