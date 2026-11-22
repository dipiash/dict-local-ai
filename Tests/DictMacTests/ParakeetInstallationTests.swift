import Foundation
import XCTest

@testable import DictLocalAI

final class ParakeetInstallationTests: XCTestCase {
  func testUsesOnlyCurrentVocabularyName() {
    let directory = URL(fileURLWithPath: "/tmp/model-directory")
    XCTAssertEqual(
      HuggingFaceModels.ultraVocabularyURL(in: directory),
      directory.appendingPathComponent("parakeet_vocab.json"))
  }

  func testReceiptCoversAllSelectedBundlesAndRejectsMutationOrUnexpectedFiles() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent(UUID().uuidString)
    defer { try? manager.removeItem(at: root) }
    let bytes = Data([1, 2, 3])
    for bundle in HuggingFaceModels.ultraBundles {
      let bundleURL = directory.appendingPathComponent(bundle)
      let weights = bundleURL.appendingPathComponent("weights")
      try manager.createDirectory(at: weights, withIntermediateDirectories: true)
      try bytes.write(to: bundleURL.appendingPathComponent("coremldata.bin"))
      try bytes.write(to: weights.appendingPathComponent("weight.bin"))
    }
    try bytes.write(to: HuggingFaceModels.ultraVocabularyURL(in: directory))
    let receipt = try HuggingFaceModels.makeReceipt(
      .ultra, revision: String(repeating: "a", count: 40), directory: directory)
    let alias = root.appendingPathComponent("model alias")
    try manager.createSymbolicLink(at: alias, withDestinationURL: directory)
    let aliasedReceipt = try HuggingFaceModels.makeReceipt(
      .ultra, revision: receipt.revision, directory: alias)
    XCTAssertEqual(aliasedReceipt.sha256, receipt.sha256)
    func verified(_ receipt: HuggingFaceReceipt) -> URL? {
      HuggingFaceModels.verifiedDirectory(.ultra, receipt: receipt, root: root)
    }
    XCTAssertEqual(verified(receipt)?.path, directory.path)
    var legacy = receipt
    legacy.format = nil
    XCTAssertNil(verified(legacy))
    let unexpected = directory.appendingPathComponent("Encoder.mlmodelc/extra.bin")
    try bytes.write(to: unexpected)
    XCTAssertNil(verified(receipt))
    try manager.removeItem(at: unexpected)
    let weight = directory.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin")
    try Data([4, 5, 6]).write(to: weight)
    XCTAssertNil(verified(receipt))
    XCTAssertTrue(manager.fileExists(atPath: weight.path))
  }

  @MainActor
  func testSavedFnShortcutIsPreservedOnReload() throws {
    let suite = "ShortcutTest-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    XCTAssertEqual(Preferences(storage: UserDefaultsPreferences(defaults: defaults)).hold, .hold)
    let shortcut = Shortcut(key: 63, modifiers: 0, label: "Fn")
    defaults.set(try JSONEncoder().encode(shortcut), forKey: "hold")
    XCTAssertEqual(Preferences(storage: UserDefaultsPreferences(defaults: defaults)).hold, shortcut)
  }
}
