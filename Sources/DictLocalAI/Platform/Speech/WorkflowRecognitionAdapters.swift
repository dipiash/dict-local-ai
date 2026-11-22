import DictApplication
import DictCore

extension RecognitionService: FileRecognizing, MeetingRecognizing {
  func makeMeetingPipeline(
    onUpdate: @escaping @MainActor @Sendable ([TranscriptSegment], Double) -> Void,
    onFailure: @escaping @MainActor @Sendable (Error) -> Void,
    onFinalize: @escaping @MainActor @Sendable ([TranscriptSegment], DiarizationAudit) -> Void
  ) async throws -> any MeetingRecognizingPipeline {
    try await makePipeline(onUpdate: onUpdate, onFailure: onFailure, onFinalize: onFinalize)
  }
}

extension MeetingRecognitionPipeline: MeetingRecognizingPipeline {}
extension MeetingAudioCapture: MeetingCapturing {}
