import Foundation

@MainActor
public protocol ModelSetupEnvironment {
  associatedtype Kind: Sendable
  associatedtype Receipt: Sendable

  func setOffline(_ offline: Bool)
  func installationDirectory(for kind: Kind) -> URL
  func preparePaths() throws
  func revision(for kind: Kind) async throws -> String
  func createInstallation(at directory: URL) throws
  func download(
    _ kind: Kind, revision: String, to directory: URL,
    progress: @escaping @MainActor @Sendable (Double?, String) -> Void
  ) async throws
  func makeReceipt(_ kind: Kind, revision: String, directory: URL) async throws -> Receipt
  func readReceipt(for kind: Kind) -> Receipt?
  func verifiedDirectory(for kind: Kind, receipt: Receipt) async -> URL?
  func removeInstallation(at directory: URL)
  func activate(_ kind: Kind, directory: URL, receipt: Receipt?) async throws
}

@MainActor
public struct ModelSetup<Environment: ModelSetupEnvironment> {
  public enum RestoreEvent {
    case checking, invalidReceipt, loaded
    case failed(Error)
  }

  public enum InstallEvent: Sendable {
    case revision(String)
    case downloading(Double?, String)
    case checking
  }

  private let environment: Environment

  public init(environment: Environment) { self.environment = environment }

  public func restore(
    _ kinds: [Environment.Kind], report: (Environment.Kind, RestoreEvent) -> Void
  ) async {
    environment.setOffline(true)
    for kind in kinds {
      guard let receipt = environment.readReceipt(for: kind) else { continue }
      report(kind, .checking)
      guard let directory = await environment.verifiedDirectory(for: kind, receipt: receipt) else {
        report(kind, .invalidReceipt)
        continue
      }
      do {
        try await environment.activate(kind, directory: directory, receipt: nil)
        report(kind, .loaded)
      } catch { report(kind, .failed(error)) }
    }
  }

  public func install(
    _ kind: Environment.Kind, report: @escaping @MainActor @Sendable (InstallEvent) -> Void
  ) async throws -> String {
    let directory = environment.installationDirectory(for: kind)
    var installed = false
    defer {
      environment.setOffline(true)
      if !installed { environment.removeInstallation(at: directory) }
    }
    try environment.preparePaths()
    let revision = try await environment.revision(for: kind)
    report(.revision(revision))
    try environment.createInstallation(at: directory)
    environment.setOffline(false)
    try await environment.download(kind, revision: revision, to: directory) {
      report(.downloading($0, $1))
    }
    environment.setOffline(true)
    report(.checking)
    let receipt = try await environment.makeReceipt(kind, revision: revision, directory: directory)
    try await environment.activate(kind, directory: directory, receipt: receipt)
    installed = true
    return revision
  }
}
