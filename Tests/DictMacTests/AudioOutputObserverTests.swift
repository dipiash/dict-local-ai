import CoreAudio
import XCTest

@testable import DictLocalAI

final class AudioOutputObserverTests: XCTestCase {
  private let speakers = AudioOutputIdentity(transport: .builtin, uid: "BuiltInSpeakerDevice")
  private let airPods = AudioOutputIdentity(
    transport: .bluetooth, uid: "AA-BB-CC-DD-EE-FF:output")

  func testFirstDeviceExclusivelySetsBaseline() {
    var tracker = AudioOutputObserver()
    XCTAssertNil(tracker.observe(speakers))
  }

  func testChangeRecordsTransportTypesAndAShortID() throws {
    var tracker = AudioOutputObserver()
    _ = tracker.observe(speakers)
    let line = try XCTUnwrap(tracker.observe(airPods))
    XCTAssertEqual(line, "from=builtin to=bluetooth device=\(airPods.shortID)")
    XCTAssertTrue(line.range(of: #"device=[0-9a-f]{4}$"#, options: .regularExpression) != nil)
  }

  func testShortIDIsTheStartOfTheSHAOfTheUID() {
    // SHA-256("abc") starts with ba7816bf.
    XCTAssertEqual(AudioOutputIdentity(transport: .usb, uid: "abc").shortID, "ba78")
  }

  func testOutputDiagnosticOmitsDeviceName() throws {
    var tracker = AudioOutputObserver()
    _ = tracker.observe(speakers)
    let named = AudioOutputIdentity(transport: .bluetooth, uid: "Test User's AirPods")
    let line = try XCTUnwrap(tracker.observe(named))
    XCTAssertFalse(line.contains("Test User"))
    XCTAssertFalse(line.contains("AirPods"))
  }

  func testRepeatedOutputNotificationProducesNoChange() {
    var tracker = AudioOutputObserver()
    _ = tracker.observe(airPods)
    XCTAssertNil(tracker.observe(airPods))
  }

  func testNextChangeBeginsFromPreviousDevice() throws {
    var tracker = AudioOutputObserver()
    _ = tracker.observe(speakers)
    _ = tracker.observe(airPods)
    let line = try XCTUnwrap(tracker.observe(speakers))
    XCTAssertEqual(line, "from=bluetooth to=builtin device=\(speakers.shortID)")
  }

  func testConnectionTypesHaveReadableDiagnosticNames() {
    typealias Transport = AudioOutputIdentity.Transport
    XCTAssertEqual(Transport(code: kAudioDeviceTransportTypeBuiltIn), .builtin)
    XCTAssertEqual(Transport(code: kAudioDeviceTransportTypeBluetooth), .bluetooth)
    XCTAssertEqual(Transport(code: kAudioDeviceTransportTypeBluetoothLE), .bluetooth)
    XCTAssertEqual(Transport(code: kAudioDeviceTransportTypeUSB), .usb)
    XCTAssertEqual(Transport(code: kAudioDeviceTransportTypeHDMI), .hdmi)
    XCTAssertEqual(Transport(code: kAudioDeviceTransportTypeAirPlay), .airplay)
    XCTAssertEqual(Transport(code: kAudioDeviceTransportTypeVirtual), .virtual)
    XCTAssertEqual(Transport(code: 0), .other)
  }
}
