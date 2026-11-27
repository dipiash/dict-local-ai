import XCTest

@testable import DictLocalAI

final class AudioRetentionPreferenceTests: XCTestCase {
  private func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  private func names(_ folder: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
  }

  @MainActor
  private func preferences(_ suite: String = UUID().uuidString) -> (Preferences, UserDefaults) {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (Preferences(storage: UserDefaultsPreferences(defaults: defaults)), defaults)
  }

  @MainActor
  func testAudioRetentionDefaultsOnAndRequiresHistory() {
    let (preferences, _) = preferences()
    XCTAssertTrue(preferences.saveAudio)
    XCTAssertTrue(preferences.keepsAudio)
    preferences.saveAudio = false
    XCTAssertFalse(preferences.keepsAudio)
    preferences.saveAudio = true
    preferences.saveHistory = false
    XCTAssertFalse(preferences.keepsAudio)
  }

  @MainActor
  func testAudioRetentionPreferencePersistsAcrossLaunches() {
    let suite = UUID().uuidString
    let (first, defaults) = preferences(suite)
    first.saveAudio = false
    let second = Preferences(storage: UserDefaultsPreferences(defaults: defaults))
    XCTAssertFalse(second.saveAudio)
    defaults.removePersistentDomain(forName: suite)
  }

  @MainActor
  func testClipboardRetentionDefaultsOnAndPersistsAcrossLaunches() {
    let suite = UUID().uuidString
    let (first, defaults) = preferences(suite)
    XCTAssertTrue(first.restoreClipboard)
    first.restoreClipboard = false
    let second = Preferences(storage: UserDefaultsPreferences(defaults: defaults))
    XCTAssertFalse(second.restoreClipboard)
    defaults.removePersistentDomain(forName: suite)
  }

  func testDisabledRetentionSkipsAudioForEveryRecordType() throws {
    let dir = folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    XCTAssertNil(HistoryAudioFile.make(kind: .meeting, enabled: false, directory: dir))
    XCTAssertNil(HistoryAudioFile.save([0.1, 0.2], enabled: false, directory: dir))
    let source = dir.appendingPathComponent("source.wav")
    XCTAssertNil(HistoryAudioFile.copy(from: source, enabled: false, directory: dir))
    XCTAssertTrue(names(dir).isEmpty)
  }

  func testEnabledRetentionCreatesAudioFile() throws {
    let dir = folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let audio = try XCTUnwrap(HistoryAudioFile.save([0.1, 0.2], enabled: true, directory: dir))
    XCTAssertTrue(audio.finalizeSynchronously())
    XCTAssertEqual(names(dir), [audio.name])
  }
}
