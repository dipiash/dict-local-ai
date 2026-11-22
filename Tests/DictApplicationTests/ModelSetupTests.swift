import DictApplication
import Foundation
import XCTest

final class ModelSetupTests: XCTestCase {
  @MainActor
  func testInstallReturnsOfflineBeforeCreatingReceiptAndActivating() async throws {
    let environment = RecordingModelEnvironment()
    let setup = ModelSetup(environment: environment)
    let revision = try await setup.install("speech") { _ in }
    XCTAssertEqual(revision, "revision")
    XCTAssertEqual(
      environment.events,
      [
        "directory", "prepare", "revision", "stage", "online", "download", "offline",
        "receipt", "activate staged", "offline",
      ])
  }

  @MainActor
  func testActivationFailureDiscardsStagingAndLeavesOfflineModeOn() async {
    let environment = RecordingModelEnvironment()
    environment.failActivation = true
    let setup = ModelSetup(environment: environment)
    do {
      _ = try await setup.install("speech") { _ in }
      XCTFail("Expected activation failure")
    } catch {
      XCTAssertEqual(Array(environment.events.suffix(3)), ["activate staged", "offline", "remove"])
    }
  }

  @MainActor
  func testRestoreSkipsInvalidReceiptAndNeverDownloads() async {
    let environment = RecordingModelEnvironment()
    let setup = ModelSetup(environment: environment)
    var invalid: [String] = []
    await setup.restore(["invalid", "valid", "missing"]) { kind, event in
      if case .invalidReceipt = event { invalid.append(kind) }
    }
    XCTAssertEqual(invalid, ["invalid"])
    XCTAssertEqual(
      environment.events,
      [
        "offline", "read invalid", "verify invalid", "read valid", "verify valid",
        "activate cached", "read missing",
      ])
  }
}

@MainActor
private final class RecordingModelEnvironment: ModelSetupEnvironment {
  enum ActivationFailure: Error { case rejected }

  private let directory = URL(fileURLWithPath: "/test-installation")
  var events: [String] = []
  var failActivation = false

  func setOffline(_ offline: Bool) { events.append(offline ? "offline" : "online") }
  func installationDirectory(for kind: String) -> URL {
    events.append("directory")
    return directory
  }

  func preparePaths() { events.append("prepare") }
  func revision(for kind: String) async -> String {
    events.append("revision")
    return "revision"
  }

  func createInstallation(at directory: URL) { events.append("stage") }
  func download(
    _ kind: String, revision: String, to directory: URL,
    progress: @escaping @MainActor @Sendable (Double?, String) -> Void
  ) async { events.append("download") }

  func makeReceipt(_ kind: String, revision: String, directory: URL) async -> String {
    events.append("receipt")
    return kind
  }

  func readReceipt(for kind: String) -> String? {
    events.append("read \(kind)")
    return kind == "missing" ? nil : kind
  }

  func verifiedDirectory(for kind: String, receipt: String) async -> URL? {
    events.append("verify \(kind)")
    return kind == "invalid" ? nil : directory
  }

  func removeInstallation(at directory: URL) { events.append("remove") }
  func activate(_ kind: String, directory: URL, receipt: String?) async throws {
    events.append(receipt == nil ? "activate cached" : "activate staged")
    if failActivation { throw ActivationFailure.rejected }
  }
}
