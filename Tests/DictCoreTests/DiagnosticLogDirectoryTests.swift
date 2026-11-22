import Foundation
import XCTest

@testable import DictCore

final class DiagnosticLogDirectoryTests: XCTestCase {
  func testPortableDefaultUsesCurrentUserLibrary() {
    let developerLibrary = URL(fileURLWithPath: "/Users/developer/Library", isDirectory: true)
    let otherMacLibrary = URL(fileURLWithPath: "/Users/guest/Library", isDirectory: true)

    XCTAssertEqual(
      DiagnosticLogDirectory.resolve(libraryDirectory: developerLibrary, overridePath: nil).path,
      "/Users/developer/Library/Logs/Dict Local AI")
    XCTAssertEqual(
      DiagnosticLogDirectory.resolve(libraryDirectory: otherMacLibrary, overridePath: nil).path,
      "/Users/guest/Library/Logs/Dict Local AI")
  }

  func testExplicitOverrideIsPreserved() {
    let library = URL(fileURLWithPath: "/Users/guest/Library", isDirectory: true)
    let path = DiagnosticLogDirectory.resolve(
      libraryDirectory: library,
      overridePath: "/tmp/dict-local-ai-debug")
    XCTAssertEqual(path.path, "/tmp/dict-local-ai-debug")
  }

  func testEmptyOverrideFallsBackToUserLibrary() {
    let library = URL(fileURLWithPath: "/Users/guest/Library", isDirectory: true)
    XCTAssertEqual(
      DiagnosticLogDirectory.resolve(libraryDirectory: library, overridePath: "").path,
      "/Users/guest/Library/Logs/Dict Local AI")
  }
}
