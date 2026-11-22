import AVFoundation
import CoreMedia
import Synchronization

@MainActor
final class MeetingAudioCapture {
  private nonisolated let processor = MeetingAudioProcessor()
  var onSamples: @Sendable ([Float], TimeInterval) -> Void {
    get { processor.state.withLock { $0.onSamples } }
    set { processor.state.withLock { $0.onSamples = newValue } }
  }
  var onFailure: @MainActor @Sendable (String) -> Void {
    get { processor.state.withLock { $0.onFailure } }
    set { processor.state.withLock { $0.onFailure = newValue } }
  }
  var onSystemAudioDetected: @MainActor @Sendable () -> Void {
    get { processor.state.withLock { $0.onSystemAudioDetected } }
    set { processor.state.withLock { $0.onSystemAudioDetected = newValue } }
  }
  private var systemTap: SystemAudioTapCapture?
  private var generation = 0

  func start() async throws {
    generation += 1
    let current = generation
    await stopResources()
    try Task.checkCancellation()
    guard generation == current else { throw CancellationError() }

    let origin = CMClockGetTime(CMClockGetHostTimeClock()).seconds
    processor.state.withLock {
      $0.converter = nil
      $0.systemAudioDetected = false
      $0.accepted = true
    }
    do {
      let capture = SystemAudioTapCapture(
        onAudio: processor.makeAudioHandler(), onFailure: processor.makeFailureHandler())
      systemTap = capture
      try await capture.start(origin: origin)
      try Task.checkCancellation()
      guard generation == current else { throw CancellationError() }
    } catch {
      if generation == current { await stopResources() }
      throw error
    }
  }

  func stop() async {
    generation += 1
    await stopResources()
  }

  private func stopResources() async {
    processor.state.withLock {
      $0.accepted = false
      $0.converter = nil
    }
    let oldTap = systemTap
    systemTap = nil
    if let oldTap { await oldTap.stop() }
  }
}

final class MeetingAudioProcessor: Sendable {
  let state = Mutex(State())

  func makeAudioHandler() -> SystemAudioTapCapture.AudioHandler {
    { [self] buffer, timestamp in
      state.withLock { $0.emit(buffer, at: timestamp) }
    }
  }

  func makeFailureHandler() -> @Sendable (String) -> Void {
    { [self] message in
      state.withLock { $0.fail(message) }
    }
  }

  struct State {
    var accepted = false
    var converter: AVAudioConverter?
    var systemAudioDetected = false
    var onSystemAudioDetected: @MainActor @Sendable () -> Void = {}
    var onSamples: @Sendable ([Float], TimeInterval) -> Void = { _, _ in }
    var onFailure: @MainActor @Sendable (String) -> Void = { _ in }
    mutating func emit(_ input: AVAudioPCMBuffer, at timestamp: Double) {
      guard accepted, timestamp.isFinite else { return }
      guard
        let target = AVAudioFormat(
          commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
          channels: 1, interleaved: false)
      else { return }
      if converter?.inputFormat != input.format {
        converter = AVAudioConverter(from: input.format, to: target)
      }
      guard let converter, input.format.sampleRate > 0 else {
        fail(L10n.text("audio.could-not-convert-audio-to"))
        return
      }
      let capacity = AVAudioFrameCount(
        ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate) + 64)
      guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
        return
      }
      nonisolated(unsafe) let input = input
      nonisolated(unsafe) var supplied = false
      var error: NSError?
      converter.convert(to: output, error: &error) { _, state in
        if supplied {
          state.pointee = .noDataNow
          return nil
        }
        supplied = true
        state.pointee = .haveData
        return input
      }
      guard error == nil, let channel = output.floatChannelData?[0] else {
        fail(
          L10n.text(
            "audio.audio-conversion-failed",
            error.map(L10n.error) ?? L10n.text("common.unavailable")))
        return
      }
      let count = Int(output.frameLength)
      guard count > 0 else { return }
      let samples = Array(UnsafeBufferPointer(start: channel, count: count))
      if !systemAudioDetected && samples.contains(where: { abs($0) > 0.0005 }) {
        systemAudioDetected = true
        DiagnosticLog.shared.event("system-audio", "non_silent_audio_confirmed")
        let notify = onSystemAudioDetected
        Task { @MainActor in notify() }
      }
      onSamples(samples, max(0, timestamp))
    }

    mutating func fail(_ message: String) {
      guard accepted else { return }
      accepted = false
      let callback = onFailure
      Task { @MainActor in callback(message) }
    }
  }
}
