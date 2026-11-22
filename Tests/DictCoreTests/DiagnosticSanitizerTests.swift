import XCTest

@testable import DictCore

final class DiagnosticSanitizerTests: XCTestCase {
  func testPrivatePathsAndTokensAreRemoved() {
    let text = "path=/Users/person/Documents/work.m4a email=example@example.com token=abc123"
    let result = DiagnosticSanitizer.scrub(text)
    XCTAssertFalse(result.contains("/Users/person"))
    XCTAssertFalse(result.contains("example@example.com"))
    XCTAssertFalse(result.contains("abc123"))
  }
  func testSpacedPathAndURLCredentialsAreRemoved() {
    let text = "url=https://unit.test/?token=example Error: /Users/Synthetic User/Private Audio.m4a"
    let result = DiagnosticSanitizer.scrub(text)
    XCTAssertFalse(result.contains("example"))
    XCTAssertFalse(result.contains("Synthetic User"))
    XCTAssertFalse(result.contains("Private Audio"))
  }
  func testMultilineAndLongValuesAreBounded() {
    let result = DiagnosticSanitizer.scrub("failure\n" + String(repeating: "a", count: 5000))
    XCTAssertFalse(result.contains("\n"))
    XCTAssertLessThanOrEqual(result.count, 2048)
  }
}
