import XCTest

@testable import DictLocalAI

final class IsolatedAppDataTests: XCTestCase {
  private func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  func testWithoutOverrideDataRemainsInApplicationSupport() {
    XCTAssertEqual(Paths.data(environment: [:]), Paths.root)
    XCTAssertEqual(Paths.data(environment: ["DICT_DATA_DIR": ""]), Paths.root)
  }

  func testDataIsolationKeepsExistingModelDirectory() {
    let dir = folder()
    let data = Paths.data(environment: ["DICT_DATA_DIR": dir.path])
    XCTAssertEqual(data.path, dir.standardizedFileURL.path)
    XCTAssertNotEqual(Paths.root.path, data.path)
    XCTAssertFalse(HuggingFaceModels.installationsRoot(.ultra).path.hasPrefix(dir.path))
  }

  @MainActor
  func testNormalLaunchKeepsUserDefaultsForPreferences() {
    XCTAssertTrue(PreferencesFactory.make(environment: [:]) is UserDefaultsPreferences)
  }

  @MainActor
  func testIsolatedPreferencesAreWrittenToOverrideDirectory() throws {
    let dir = folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let environment = ["DICT_DATA_DIR": dir.path]
    let first = PreferencesFactory.make(environment: environment)
    XCTAssertTrue(first.saveAudio)
    first.saveAudio = false
    first.enabled = false
    first.microphone = "Desk mic"
    first.hold = .toggle
    let second = PreferencesFactory.make(environment: environment)
    XCTAssertFalse(second.saveAudio)
    XCTAssertFalse(second.enabled)
    XCTAssertTrue(second.saveHistory)
    XCTAssertEqual(second.microphone, "Desk mic")
    XCTAssertEqual(second.hold, .toggle)
    let file = dir.appendingPathComponent("preferences.json")
    let text = try String(contentsOf: file, encoding: .utf8)
    XCTAssertTrue(text.contains("\"historyAudio\" : false"), text)
  }
}
