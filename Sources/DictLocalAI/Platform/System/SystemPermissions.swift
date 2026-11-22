import AVFoundation
import AppKit
import ApplicationServices

@MainActor
enum SystemPermissions {
  static var microphone: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
  static var accessibility: Bool { AXIsProcessTrusted() }
  static var inputMonitoring: Bool { CGPreflightListenEventAccess() }

  static func requestMicrophone() async { _ = await AVCaptureDevice.requestAccess(for: .audio) }

  static func requestAccessibility() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  static func requestInputMonitoring() { _ = CGRequestListenEventAccess() }

  static func openPrivacy(_ anchor: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
      NSWorkspace.shared.open(url)
    }
  }
}
