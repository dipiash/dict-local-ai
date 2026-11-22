import DictCore
import Foundation

public struct FileRecognitionOutput: Sendable {
  public let segments: [TranscriptSegment]
  public let diarizationMethod: String
  public let audit: DiarizationAudit?
  public let asrWarnings: [String]
  public let splitCandidates: [DiarizationSplitReview.Candidate]

  public init(
    segments: [TranscriptSegment], diarizationMethod: String, audit: DiarizationAudit?,
    asrWarnings: [String], splitCandidates: [DiarizationSplitReview.Candidate]
  ) {
    self.segments = segments
    self.diarizationMethod = diarizationMethod
    self.audit = audit
    self.asrWarnings = asrWarnings
    self.splitCandidates = splitCandidates
  }

  public var reviewCandidates: [DiarizationAudit.PipelineObservation] {
    (audit?.pipelineObservations ?? []).filter { $0.stage.hasPrefix("nemotron3_candidate_") }
  }
}

public protocol FileRecognizing: Sendable {
  func transcribeFile(
    _ url: URL, session: RecognitionSession,
    identifySpeakers: Bool, compareChunks: Bool,
    update: @escaping @MainActor @Sendable (Double, Double, [TranscriptSegment]) -> Void,
    stage: @escaping @MainActor @Sendable (String) -> Void
  ) async throws -> FileRecognitionOutput
}

@MainActor
public final class FileTranscriptionWorkflow {
  public enum Blocker { case speechModel, speakerModels, activeRecording }
  public enum Completion {
    case success, warnings, speechOnly, cancelled
    case failed(Error)
    case diarizationFailed(Error)
  }

  private let modes: ModeCoordinator
  private let writer: @Sendable () throws -> any RecordingWriter
  private var lease: ModeCoordinator.Lease?

  public init(
    modes: ModeCoordinator, writer: @escaping @Sendable () throws -> any RecordingWriter
  ) {
    self.modes = modes
    self.writer = writer
  }

  public func blocker(
    ready: () -> Bool, identifySpeakers: Bool, speakerModelsReady: () -> Bool
  ) -> Blocker? {
    guard ready() else { return .speechModel }
    guard !identifySpeakers || speakerModelsReady() else { return .speakerModels }
    return modes.active == nil ? nil : .activeRecording
  }

  public func begin(
    ready: () -> Bool, identifySpeakers: Bool, speakerModelsReady: () -> Bool
  ) -> Bool {
    guard
      blocker(
        ready: ready, identifySpeakers: identifySpeakers, speakerModelsReady: speakerModelsReady
      ) == nil, let acquired = modes.acquire(.file)
    else { return false }
    lease = acquired
    return true
  }

  public func makeTranscript(
    source: String, duration: Double, identifySpeakers: Bool
  ) -> FileTranscript {
    var document = FileTranscript(source: source, duration: duration)
    document.speakerRecognitionEnabled = identifySpeakers
    return document
  }

  public func append(
    _ segments: [TranscriptSegment], source: String, duration: Double, until end: Double,
    identifySpeakers: Bool, to transcript: inout FileTranscript?
  ) {
    if transcript?.duration == 0 {
      transcript = makeTranscript(
        source: source, duration: duration, identifySpeakers: identifySpeakers)
    }
    transcript?.processedUntil = end
    transcript?.segments.append(contentsOf: segments)
  }

  public func apply(
    _ output: FileRecognitionOutput, duration: Double, to transcript: inout FileTranscript?
  ) {
    transcript?.segments = output.segments
    transcript?.asrWarnings = output.asrWarnings.isEmpty ? nil : output.asrWarnings
    transcript?.diarizationMethod = output.diarizationMethod
    transcript?.processedUntil = duration
  }

  public func finish(
    _ result: Result<Void, Error>,
    transcript: inout FileTranscript?,
    identifySpeakers: Bool
  ) -> Completion {
    transcript?.suggestNames()
    modes.release(lease)
    lease = nil
    switch result {
    case .success:
      transcript?.complete = true
      if transcript?.asrWarnings?.isEmpty == false { return .warnings }
      return transcript?.diarizationMethod == "asr-only" ? .speechOnly : .success
    case .failure(let error):
      if error is CancellationError { return .cancelled }
      if let current = transcript, current.duration > 0,
        current.processedUntil >= current.duration, identifySpeakers
      {
        transcript?.speakerRecognitionEnabled = false
        transcript?.diarizationMethod = "diarization-failed"
        return .diarizationFailed(error)
      }
      return .failed(error)
    }
  }

  @discardableResult
  public func saveIfEligible(_ transcript: FileTranscript?, enabled: Bool) throws -> Bool {
    guard enabled, let transcript, !transcript.segments.isEmpty, transcript.processedUntil > 0
    else { return false }
    _ = try writer().create(
      transcript, category: .file, id: UUID(), date: transcript.startedAt ?? Date())
    return true
  }
}

extension FileTranscriptionWorkflow.Completion {
  public var retryable: Bool {
    switch self {
    case .failed, .diarizationFailed: true
    default: false
    }
  }

  public var diagnosticOutcome: String {
    switch self {
    case .success, .warnings, .speechOnly: "success"
    case .cancelled: "cancelled"
    case .failed, .diarizationFailed: "failed"
    }
  }
}
