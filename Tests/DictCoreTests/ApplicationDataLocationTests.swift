import Foundation
import XCTest

@testable import DictCore

final class ApplicationDataLocationTests: XCTestCase {
  private let support = URL(
    fileURLWithPath: "/Users/guest/Library/Application Support", isDirectory: true)

  func testDefaultDataLocationIsInApplicationSupport() {
    XCTAssertEqual(
      ApplicationDataLocation.resolve(applicationSupport: support, overridePath: nil).path,
      "/Users/guest/Library/Application Support/Dict Local AI")
  }

  func testBlankOverridePreservesDefault() {
    XCTAssertEqual(
      ApplicationDataLocation.resolve(applicationSupport: support, overridePath: "").path,
      "/Users/guest/Library/Application Support/Dict Local AI")
  }

  func testCustomDataLocationTakesPrecedence() {
    XCTAssertEqual(
      ApplicationDataLocation.resolve(
        applicationSupport: support, overridePath: "/tmp/dict-ui-test"
      ).path,
      "/tmp/dict-ui-test")
  }

  func testDataLocationUsesEnvironmentOverride() {
    XCTAssertEqual(
      ApplicationDataLocation.override(environment: ["DICT_DATA_DIR": "/tmp/dict-ui-test"])?.path,
      "/tmp/dict-ui-test")
    XCTAssertNil(ApplicationDataLocation.override(environment: [:]))
    XCTAssertNil(ApplicationDataLocation.override(environment: ["DICT_DATA_DIR": ""]))
  }
}
