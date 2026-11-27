import CoreAudio
import CryptoKit
import Foundation

/// Represent output devices in logs by connection type and a short identifier.
struct AudioOutputIdentity: Equatable {
  enum Transport: String {
    case builtin, bluetooth, usb, hdmi, airplay, virtual, other

    init(code: UInt32) {
      switch code {
      case kAudioDeviceTransportTypeBuiltIn: self = .builtin
      case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
        self = .bluetooth
      case kAudioDeviceTransportTypeUSB: self = .usb
      case kAudioDeviceTransportTypeHDMI: self = .hdmi
      case kAudioDeviceTransportTypeAirPlay: self = .airplay
      case kAudioDeviceTransportTypeVirtual: self = .virtual
      default: self = .other
      }
    }
  }

  let transport: Transport
  let uid: String

  // Log only the four-character digest prefix to distinguish device changes.
  var shortID: String {
    SHA256.hash(data: Data(uid.utf8)).prefix(2).map { String(format: "%02x", $0) }.joined()
  }
}

struct AudioOutputObserver {
  private var current: AudioOutputIdentity?

  // Use the first device as the reference point for later changes.
  mutating func observe(_ device: AudioOutputIdentity) -> String? {
    defer { current = device }
    guard let current, current.uid != device.uid else { return nil }
    return
      "from=\(current.transport.rawValue) to=\(device.transport.rawValue) device=\(device.shortID)"
  }
}
