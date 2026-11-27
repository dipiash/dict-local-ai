import AVFoundation
import AudioToolbox
import CoreAudio
import DictApplication
import DictCore
import Synchronization

struct Microphone: Identifiable {
  let id: String
  let name: String
  let device: AudioDeviceID
}

final class CapturedAudio: Sendable {
  struct State {
    var samples: [Float] = []
    var running = false
    var generation = UUID()
    var failed = false
    var energy: Float = 0
  }
  let state = Mutex(State())
}

actor AudioCapture: DictationCapturing {
  private var engine: AVAudioEngine?
  private nonisolated let captured = CapturedAudio()
  private let onInterruption: @MainActor @Sendable () -> Void
  private var observer: NSObjectProtocol?
  private var tapInstalled = false
  private var activeRequestID: UUID?
  init(onInterruption: @escaping @MainActor @Sendable () -> Void) {
    self.onInterruption = onInterruption
  }
  nonisolated var isRunning: Bool { captured.state.withLock { $0.running } }
  nonisolated var count: Int { captured.state.withLock { $0.samples.count } }
  nonisolated var level: Float { captured.state.withLock { $0.energy } }
  nonisolated func copy(from start: Int = 0) -> [Float] {
    // From 0 the array is shared, not copied: a 30 minute buffer is about 115 MB.
    captured.state.withLock {
      start <= 0 ? $0.samples : Array($0.samples[min(start, $0.samples.count)...])
    }
  }
  nonisolated func erase() {
    captured.state.withLock {
      $0.samples.removeAll()
      $0.energy = 0
    }
  }
  func start(deviceID: String, requestID: UUID) throws {
    stopEngine()
    activeRequestID = requestID
    let engine = AVAudioEngine()
    self.engine = engine
    erase()
    DiagnosticLog.shared.event("audio", "engine_init_begin")
    let node = engine.inputNode
    DiagnosticLog.shared.event("audio", "engine_init_end")
    if !deviceID.isEmpty {
      guard let selected = Self.microphones().first(where: { $0.id == deviceID }),
        let unit = node.audioUnit
      else {
        throw AppFailure("audio.the-selected-microphone-is-unavailable")
      }
      var device = selected.device
      let status = AudioUnitSetProperty(
        unit, kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
      guard status == noErr else { throw AppFailure("audio.could-not-connect-to-the") }
    }
    let source = node.outputFormat(forBus: 0)
    guard source.sampleRate > 0, source.channelCount > 0,
      let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
      let converter = AVAudioConverter(from: source, to: target)
    else { throw AppFailure("audio.the-microphone-is-not-ready") }
    let generation = UUID()
    captured.state.withLock {
      $0.running = true
      $0.generation = generation
      $0.failed = false
    }
    let sampleRate = source.sampleRate
    let channelCount = source.channelCount
    node.installTap(
      onBus: 0, bufferSize: 4096, format: source,
      block: Self.makeTap(
        captured: captured, converter: converter, generation: generation,
        sampleRate: sampleRate, interrupted: onInterruption))
    tapInstalled = true
    do {
      DiagnosticLog.shared.event("audio", "engine_start_begin")
      engine.prepare()
      try engine.start()
      DiagnosticLog.shared.event("audio", "engine_start_end")
      observer = NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
      ) { [weak self] _ in
        Task {
          await self?.handleConfigurationChange(
            generation: generation, sampleRate: sampleRate, channelCount: channelCount)
        }
      }
    } catch {
      stop(requestID: requestID)
      throw error
    }
  }
  private func handleConfigurationChange(
    generation: UUID, sampleRate: Double, channelCount: AVAudioChannelCount
  ) async {
    guard let engine,
      captured.state.withLock({ $0.running && $0.generation == generation })
    else { return }
    let current = engine.inputNode.outputFormat(forBus: 0)
    if !engine.isRunning || current.sampleRate != sampleRate
      || current.channelCount != channelCount
    {
      await onInterruption()
    }
  }

  // Core Audio runs this callback on a separate queue.
  nonisolated static func makeTap(
    captured: CapturedAudio, converter: AVAudioConverter, generation: UUID,
    sampleRate: Double, interrupted: (@MainActor @Sendable () -> Void)?
  ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
    let conversion = Mutex(converter)
    return { @Sendable buffer, _ in
      guard captured.state.withLock({ $0.running && $0.generation == generation && !$0.failed })
      else { return }
      let converted: [Float]? = conversion.withLock { converter in
        let capacity = AVAudioFrameCount(
          ceil(Double(buffer.frameLength) * 16_000 / sampleRate) + 64)
        guard
          let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity)
        else { return nil }
        nonisolated(unsafe) let buffer = buffer
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
          if supplied {
            status.pointee = .noDataNow
            return nil
          }
          supplied = true
          status.pointee = .haveData
          return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
      }
      guard let converted else {
        let valid = captured.state.withLock { state in
          guard state.generation == generation, state.running, !state.failed else { return false }
          state.failed = true
          return true
        }
        if valid {
          Task { @MainActor in
            guard captured.state.withLock({ $0.running && $0.generation == generation }) else {
              return
            }
            interrupted?()
          }
        }
        return
      }
      captured.state.withLock { state in
        guard state.running, state.generation == generation, !state.failed else { return }
        let samples = converted.prefix(max(0, AudioWindow.maximumSamples - state.samples.count))
        state.samples.append(contentsOf: samples)
        if !samples.isEmpty {
          state.energy = min(
            1, sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)) * 8)
        }
      }
    }
  }

  func stop(requestID: UUID, discard: Bool = false) {
    guard activeRequestID == requestID else {
      if discard && activeRequestID == nil { erase() }
      return
    }
    stopEngine()
    if discard { erase() }
  }
  private func stopEngine() {
    let wasRunning = captured.state.withLock { state in
      let running = state.running
      state.running = false
      state.generation = UUID()
      return running
    }
    if let observer {
      NotificationCenter.default.removeObserver(observer)
      self.observer = nil
    }
    if let engine {
      if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
      if wasRunning || engine.isRunning { engine.stop() }
    }
    tapInstalled = false
    engine = nil
    activeRequestID = nil
  }

  nonisolated static func microphones() -> [Microphone] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
      return []
    }
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else {
      return []
    }
    func text(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
      var property = AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
      // Core Audio transfers ownership of these strings.
      var value: Unmanaged<CFString>?
      var bytes = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
      guard AudioObjectGetPropertyData(id, &property, 0, nil, &bytes, &value) == noErr else {
        return nil
      }
      return value?.takeRetainedValue() as String?
    }
    return devices.compactMap { device in
      var property = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
      var bytes: UInt32 = 0
      guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &bytes) == noErr, bytes > 0,
        let uid = text(device, kAudioDevicePropertyDeviceUID),
        let name = text(device, kAudioObjectPropertyName)
      else { return nil }
      return Microphone(id: uid, name: name, device: device)
    }
  }
}
