import DictApplication
import DictCore

extension RecognitionService: DictationRecognizing {
  func makeDictationPipeline(
    onUpdate: @escaping @MainActor @Sendable ([TranscriptSegment], Double) -> Void,
    onFailure: @escaping @MainActor @Sendable (Error) -> Void
  ) async throws -> any DictationRecognizingPipeline {
    try await makePipeline(singleSpeaker: true, onUpdate: onUpdate, onFailure: onFailure)
  }
}

extension MeetingRecognitionPipeline: DictationRecognizingPipeline {}
