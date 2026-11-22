import DictApplication
import FluidAudio
import Foundation

@MainActor
struct HuggingFaceModelEnvironment: ModelSetupEnvironment {
  let recognizer: RecognitionService

  func setOffline(_ offline: Bool) { ModelHub.offlineMode = offline }

  func installationDirectory(for kind: ManagedModel) -> URL {
    HuggingFaceModels.installationsRoot(kind).appendingPathComponent(
      UUID().uuidString, isDirectory: true)
  }

  func preparePaths() throws { try Paths.prepare() }

  func revision(for kind: ManagedModel) async throws -> String {
    try await HuggingFaceModels.revision(for: kind)
  }

  func createInstallation(at directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func download(
    _ kind: ManagedModel, revision: String, to directory: URL,
    progress: @escaping @MainActor @Sendable (Double?, String) -> Void
  ) async throws {
    try await HuggingFaceModels.download(
      kind, revision: revision, to: directory, progress: progress)
  }

  func makeReceipt(_ kind: ManagedModel, revision: String, directory: URL) async throws
    -> HuggingFaceReceipt
  {
    try await Task.detached(priority: .utility) {
      try HuggingFaceModels.makeReceipt(kind, revision: revision, directory: directory)
    }.value
  }

  func readReceipt(for kind: ManagedModel) -> HuggingFaceReceipt? { HuggingFaceModels.read(kind) }

  func verifiedDirectory(for kind: ManagedModel, receipt: HuggingFaceReceipt) async -> URL? {
    let root = HuggingFaceModels.installationsRoot(kind)
    return await Task.detached(priority: .utility) {
      HuggingFaceModels.verifiedDirectory(kind, receipt: receipt, root: root)
    }.value
  }

  func removeInstallation(at directory: URL) { try? FileManager.default.removeItem(at: directory) }

  func activate(_ kind: ManagedModel, directory: URL, receipt: HuggingFaceReceipt?) async throws {
    let publish: @Sendable () throws -> Void = {
      if let receipt { try HuggingFaceModels.store(kind, receipt: receipt) }
    }
    switch kind {
    case .ultra: try await recognizer.load(directory, publish: publish)
    case .nemotron: try await recognizer.loadSpeakerModels(directory, publish: publish)
    }
  }
}
