import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

final class SystemAudioTapCapture: @unchecked Sendable {
  typealias AudioHandler = @Sendable (AVAudioPCMBuffer, Double) -> Void
  private let onAudio: AudioHandler
  private let onFailure: @Sendable (String) -> Void
  private let controlQueue = DispatchQueue(label: "dict.systemtap.control", qos: .userInitiated)
  private let ioQueue = DispatchQueue(label: "dict.systemtap.io", qos: .userInteractive)
  private let workQueue = DispatchQueue(label: "dict.systemtap.processing", qos: .userInitiated)

  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateID = AudioObjectID(kAudioObjectUnknown)
  private var ioProc: AudioDeviceIOProcID?
  private var outputUID = ""
  private var outputChanges = AudioOutputObserver()
  private var listeners:
    [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
  private var pendingRebuild: DispatchWorkItem?
  private var running = false
  private var origin = 0.0
  private var generation: UInt64 = 0
  private let validity = Mutex((active: false, epoch: UInt64(0)))

  init(onAudio: @escaping AudioHandler, onFailure: @escaping @Sendable (String) -> Void) {
    self.onAudio = onAudio
    self.onFailure = onFailure
  }

  func start(origin: Double) async throws {
    try await withCheckedThrowingContinuation { continuation in
      controlQueue.async {
        self.teardown()
        self.outputChanges = AudioOutputObserver()
        self.origin = origin
        self.running = true
        self.generation &+= 1
        self.validity.withLock { $0 = (active: true, epoch: self.generation) }
        do {
          try self.build()
          continuation.resume()
        } catch {
          self.running = false
          self.validity.withLock { $0.active = false }
          self.teardown()
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func stop() async {
    await withCheckedContinuation { continuation in
      controlQueue.async {
        self.running = false
        self.generation &+= 1
        self.validity.withLock { $0.active = false }
        self.teardown()
        self.workQueue.async { continuation.resume() }
      }
    }
  }

  private func build() throws {
    let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcessIDs())
    description.uuid = UUID()
    description.isPrivate = true
    description.muteBehavior = .unmuted
    try check(
      L10n.text("audio.create-a-system-audio-tap"),
      AudioHardwareCreateProcessTap(description, &tapID))

    outputUID = try currentOutputUID()
    if let device = currentAudioOutput() { _ = outputChanges.observe(device) }
    let aggregate: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Dict Local AI Audio Tap",
      kAudioAggregateDeviceUIDKey: "app.dictlocalai.tap.\(UUID().uuidString)",
      kAudioAggregateDeviceMainSubDeviceKey: outputUID,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
      kAudioAggregateDeviceTapListKey: [
        [
          kAudioSubTapUIDKey: description.uuid.uuidString,
          kAudioSubTapDriftCompensationKey: true,
        ]
      ],
    ]
    try check(
      L10n.text("audio.create-a-private-aggregate-audio"),
      AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))
    try waitUntilAlive()

    var asbd = AudioStreamBasicDescription()
    try read(tapID, kAudioTapPropertyFormat, into: &asbd)
    // A Bluetooth profile change can leave the tap rate out of date.
    var deviceRate = Float64(0)
    try read(aggregateID, kAudioDevicePropertyNominalSampleRate, into: &deviceRate)
    if deviceRate > 0 { asbd.mSampleRate = deviceRate }
    guard asbd.mSampleRate > 0, let format = AVAudioFormat(streamDescription: &asbd) else {
      throw AppFailure("audio.unsupported-system-audio-format")
    }
    let formatHolder = TapAudioFormat(format)
    let currentGeneration = generation
    let currentOrigin = origin
    try check(
      L10n.text("audio.create-the-core-audio-ioproc"),
      AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, ioQueue) {
        [weak self, formatHolder] cycleTime, inputData, inputTime, _, _ in
        guard let self else { return }
        guard let copied = Self.copyBuffer(inputData, format: formatHolder.format) else { return }
        let hostTime =
          inputTime.pointee.mHostTime != 0
          ? inputTime.pointee.mHostTime : cycleTime.pointee.mHostTime
        let seconds = hostTime != 0 ? AVAudioTime.seconds(forHostTime: hostTime) : 0
        let delivery = TapPCMDelivery(buffer: copied, time: max(0, seconds - currentOrigin))
        self.workQueue.async { [weak self] in
          guard let self else { return }
          // AudioDeviceStop can block the control queue.
          let valid = self.validity.withLock {
            $0.active && $0.epoch == currentGeneration
          }
          guard valid else { return }
          self.onAudio(delivery.buffer, delivery.time)
        }
      })
    try check(L10n.text("audio.start-system-audio-capture"), AudioDeviceStart(aggregateID, ioProc))
    DiagnosticLog.shared.event("system-audio", "tap_started", "sampleRate=\(format.sampleRate)")

    observe(tapID, kAudioTapPropertyFormat)
    observe(aggregateID, kAudioDevicePropertyNominalSampleRate)
    observe(
      AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice)
    observe(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
  }

  // An aggregate device can place hardware input before the tap buffers.
  private static func copyBuffer(
    _ input: UnsafePointer<AudioBufferList>, format: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let sourceBuffers = UnsafeMutableAudioBufferListPointer(
      UnsafeMutablePointer(mutating: input))
    let needed = format.isInterleaved ? 1 : Int(format.channelCount)
    guard sourceBuffers.count >= needed, needed > 0 else { return nil }
    let description = format.streamDescription
    let stride = Int(description.pointee.mBytesPerFrame)
    guard stride > 0 else { return nil }
    let firstIndex = sourceBuffers.count - needed
    let frames = Int(sourceBuffers[firstIndex].mDataByteSize) / stride
    guard frames > 0, frames <= 192_000,
      let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
    else { return nil }
    output.frameLength = AVAudioFrameCount(frames)
    let destination = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
    guard destination.count == needed else { return nil }
    for i in 0..<needed {
      let src = sourceBuffers[firstIndex + i]
      guard let srcData = src.mData, let dstData = destination[i].mData else { return nil }
      let bytes = frames * stride
      guard bytes <= Int(src.mDataByteSize), bytes <= Int(destination[i].mDataByteSize)
      else { return nil }
      memcpy(dstData, srcData, bytes)
      destination[i].mDataByteSize = UInt32(bytes)
    }
    return output
  }

  private func observe(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.scheduleRebuild()
    }
    if AudioObjectAddPropertyListenerBlock(object, &address, controlQueue, listener) == noErr {
      listeners.append((object, address, listener))
    }
  }

  private func scheduleRebuild() {
    guard running else { return }
    if let device = currentAudioOutput(), let change = outputChanges.observe(device) {
      DiagnosticLog.shared.event("meeting", "output_device_changed", change)
    }
    pendingRebuild?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self, self.running else { return }
      self.pendingRebuild = nil
      self.generation &+= 1
      self.validity.withLock { $0 = (active: true, epoch: self.generation) }
      self.teardown()
      do {
        try self.build()
      } catch {
        self.running = false
        self.validity.withLock { $0.active = false }
        self.teardown()
        DiagnosticLog.shared.event("system-audio", "rebuild_failed", "error=\(type(of: error))")
        self.onFailure(
          L10n.text("audio.system-audio-stopped-after-the", L10n.error(error)))
      }
    }
    DiagnosticLog.shared.event("system-audio", "output_changed", "rebuild_in=1.5s")
    pendingRebuild = item
    controlQueue.asyncAfter(deadline: .now() + 1.5, execute: item)
  }

  private func teardown() {
    pendingRebuild?.cancel()
    pendingRebuild = nil
    for (object, originalAddress, listener) in listeners {
      var address = originalAddress
      AudioObjectRemovePropertyListenerBlock(object, &address, controlQueue, listener)
    }
    listeners.removeAll()
    if aggregateID != kAudioObjectUnknown {
      if let ioProc {
        _ = AudioDeviceStop(aggregateID, ioProc)
        _ = AudioDeviceDestroyIOProcID(aggregateID, ioProc)
      }
      _ = AudioHardwareDestroyAggregateDevice(aggregateID)
    }
    if tapID != kAudioObjectUnknown { _ = AudioHardwareDestroyProcessTap(tapID) }
    ioProc = nil
    aggregateID = AudioObjectID(kAudioObjectUnknown)
    tapID = AudioObjectID(kAudioObjectUnknown)
    outputUID = ""
  }

  private func waitUntilAlive() throws {
    for _ in 0..<30 {
      var alive: UInt32 = 0
      if (try? read(aggregateID, kAudioDevicePropertyDeviceIsAlive, into: &alive)) != nil,
        alive != 0
      {
        return
      }
      Thread.sleep(forTimeInterval: 0.1)
    }
    throw AppFailure("audio.the-macos-audio-device-did")
  }

  private func defaultAudioOutput() throws -> AudioObjectID {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var output = AudioObjectID(kAudioObjectUnknown)
    do {
      try read(system, kAudioHardwarePropertyDefaultSystemOutputDevice, into: &output)
    } catch {
      try read(system, kAudioHardwarePropertyDefaultOutputDevice, into: &output)
    }
    guard output != kAudioObjectUnknown else {
      throw AppFailure("audio.no-system-audio-output-device")
    }
    return output
  }

  // Keep device lookup failures isolated from the capture pipeline.
  private func currentAudioOutput() -> AudioOutputIdentity? {
    guard let output = try? defaultAudioOutput(),
      let uid = try? deviceUID(output)
    else { return nil }
    var code: UInt32 = 0
    _ = try? read(output, kAudioDevicePropertyTransportType, into: &code)
    return AudioOutputIdentity(transport: .init(code: code), uid: uid)
  }

  private func currentOutputUID() throws -> String {
    try deviceUID(try defaultAudioOutput())
  }

  private func deviceUID(_ device: AudioObjectID) throws -> String {
    var uid: Unmanaged<CFString>?
    try read(device, kAudioDevicePropertyDeviceUID, into: &uid)
    guard let uid else { throw AppFailure("audio.could-not-get-the-audio") }
    return uid.takeRetainedValue() as String
  }

  private func excludedProcessIDs() -> [AudioObjectID] {
    var pid = pid_t(ProcessInfo.processInfo.processIdentifier)
    var id = AudioObjectID(kAudioObjectUnknown)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafePointer(to: &pid) { pointer in
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address,
        UInt32(MemoryLayout<pid_t>.size), pointer, &size, &id)
    }
    return status == noErr && id != kAudioObjectUnknown ? [id] : []
  }

  private func read<T: BitwiseCopyable>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T
  ) throws {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    try check(
      L10n.text("audio.read-core-audio", "\(selector)"),
      AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value))
  }

  private func check(_ operation: String, _ status: OSStatus) throws {
    guard status == noErr else {
      throw AppFailure("audio.system-audio-error", "\(operation)", "\(status)")
    }
  }
}

private final class TapAudioFormat: @unchecked Sendable {
  let format: AVAudioFormat
  init(_ format: AVAudioFormat) { self.format = format }
}

private final class TapPCMDelivery: @unchecked Sendable {
  let buffer: AVAudioPCMBuffer
  let time: Double
  init(buffer: AVAudioPCMBuffer, time: Double) {
    self.buffer = buffer
    self.time = time
  }
}
