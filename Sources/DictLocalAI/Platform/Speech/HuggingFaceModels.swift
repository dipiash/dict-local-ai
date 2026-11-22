import CryptoKit
import DictApplication
import DictCore
import FluidAudio
import Foundation

extension ManagedModel {
  var repository: String {
    switch self {
    case .ultra: "FluidInference/parakeet-ultra-coreml"
    case .nemotron: "FluidInference/nemotron-3-diarization-coreml"
    }
  }
}

struct HuggingFaceReceipt: Codable, Sendable {
  let repository: String
  let revision: String
  let localPath: String
  let installedAt: Date
  let sha256: [String: String]
  var format: Int? = nil
}

enum HuggingFaceModels {
  static let ultraBundles = ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"]
    .map { $0 + ".mlmodelc" }
  static let vocabularyName = "parakeet_vocab.json"
  static let silenceName = "learnable_sil_emb.bin"
  static let speakerPresets: [Nemotron3Config] = [.fast32, .fast128]
  static let receiptFormat = 2

  static func ultraVocabularyURL(in directory: URL) -> URL {
    directory.appendingPathComponent(vocabularyName)
  }

  static func installationsRoot(_ model: ManagedModel) -> URL {
    Paths.root.appendingPathComponent("Models/Verified/\(model.rawValue)", isDirectory: true)
  }

  private static func receiptURL(_ model: ManagedModel) -> URL {
    Paths.root.appendingPathComponent("Models/receipts/\(model.rawValue).json")
  }

  static func read(_ model: ManagedModel) -> HuggingFaceReceipt? {
    guard let data = try? Data(contentsOf: receiptURL(model)),
      let receipt = try? JSONDecoder().decode(HuggingFaceReceipt.self, from: data),
      receipt.repository == model.repository, validRevision(receipt.revision)
    else { return nil }
    return receipt
  }

  static func store(_ model: ManagedModel, receipt: HuggingFaceReceipt) throws {
    let url = receiptURL(model)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
  }

  static func makeReceipt(
    _ model: ManagedModel, revision: String, directory: URL
  ) throws -> HuggingFaceReceipt {
    HuggingFaceReceipt(
      repository: model.repository, revision: revision,
      localPath: directory.standardizedFileURL.path, installedAt: Date(),
      sha256: try digests(for: model, in: directory), format: receiptFormat)
  }

  static func verifiedDirectory(
    _ model: ManagedModel, receipt: HuggingFaceReceipt, root: URL
  ) -> URL? {
    let directory = URL(fileURLWithPath: receipt.localPath, isDirectory: true).standardizedFileURL
    guard receipt.format == receiptFormat, receipt.repository == model.repository,
      validRevision(receipt.revision),
      directory.deletingLastPathComponent().path == root.standardizedFileURL.path,
      UUID(uuidString: directory.lastPathComponent) != nil,
      directory.resolvingSymlinksInPath().path
        == root.resolvingSymlinksInPath().appendingPathComponent(directory.lastPathComponent).path,
      let actual = try? digests(for: model, in: directory), actual == receipt.sha256
    else { return nil }
    return directory
  }

  private static func digests(for model: ManagedModel, in directory: URL) throws -> [String: String]
  {
    let bundles = model == .ultra ? ultraBundles : speakerPresets.map(\.modelFileName)
    let companion = model == .ultra ? vocabularyName : silenceName
    var digests = [companion: try sha256(directory.appendingPathComponent(companion))]
    let manager = FileManager.default
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
    for bundle in bundles {
      let root = directory.appendingPathComponent(bundle, isDirectory: true)
      let properties = try root.resourceValues(forKeys: keys)
      guard properties.isDirectory == true, properties.isSymbolicLink == false else {
        throw AppFailure("models.could-not-verify-the-model")
      }
      var enumerationError: Error?
      let entries = manager.enumerator(
        at: root, includingPropertiesForKeys: Array(keys),
        errorHandler: { _, error in
          enumerationError = error
          return false
        })
      guard let entries else { throw AppFailure("models.could-not-read-the-model") }
      let prefix = root.resolvingSymlinksInPath().path + "/"
      for case let file as URL in entries {
        let properties = try file.resourceValues(forKeys: keys)
        guard properties.isSymbolicLink == false else {
          throw AppFailure("models.could-not-verify-the-model")
        }
        if properties.isDirectory == true { continue }
        let filePath = file.resolvingSymlinksInPath().path
        guard filePath.hasPrefix(prefix) else {
          throw AppFailure("models.could-not-verify-the-model-file")
        }
        let path = filePath.dropFirst(prefix.count)
        digests["\(bundle)/\(path)"] = try sha256(file)
      }
      if let enumerationError { throw enumerationError }
      guard digests["\(bundle)/coremldata.bin"] != nil,
        digests["\(bundle)/weights/weight.bin"] != nil
      else { throw AppFailure("models.some-model-files-are-missing") }
    }
    return digests
  }

  private static func sha256(_ file: URL) throws -> String {
    let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard properties.isRegularFile == true, properties.isSymbolicLink == false else {
      throw AppFailure("models.could-not-verify-the-model-file")
    }
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
      hash.update(data: data)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func validRevision(_ revision: String) -> Bool {
    revision.utf8.count == 40
      && revision.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  static func revision(for model: ManagedModel) async throws -> String {
    if let receipt = read(model) { return receipt.revision }
    guard let url = URL(string: "https://huggingface.co/api/models/\(model.repository)") else {
      throw AppFailure("models.invalid-model-address")
    }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let sha = object["sha"] as? String, validRevision(sha)
    else { throw AppFailure("models.hugging-face-did-not-return") }
    return sha
  }

  @MainActor
  static func download(
    _ model: ManagedModel, revision: String, to directory: URL,
    progress: @escaping @MainActor @Sendable (Double?, String) -> Void
  ) async throws {
    let repo: Repo = model == .ultra ? .parakeetUltra : .nemotron3Diarization
    var pins = ModelRegistry.revisionOverrides
    pins[model.repository] = revision
    ModelRegistry.baseURL = "https://huggingface.co"
    ModelRegistry.revisionOverrides = pins
    let bundles =
      model == .ultra
      ? ultraBundles : speakerPresets.map { "\($0.hubSubdirectory)/\($0.modelFileName)" }
    let incoming = directory.appendingPathComponent("download", isDirectory: true)
    let total = Double(bundles.count + 1)
    for (index, bundle) in bundles.enumerated() {
      let name = URL(fileURLWithPath: bundle).lastPathComponent
      try await ModelHub.download(
        repo, subdirectory: bundle, to: incoming,
        progressHandler: { state in
          Task { @MainActor in
            progress((Double(index) + state.fractionCompleted) / total, model.title)
          }
        })
      try FileManager.default.moveItem(
        at: incoming.appendingPathComponent(bundle), to: directory.appendingPathComponent(name))
    }
    let companion = model == .ultra ? vocabularyName : silenceName
    let url = try ModelRegistry.resolveModel(repo.remotePath, companion)
    let data = try await ModelHub.fetchFile(from: url, description: companion)
    try data.write(to: directory.appendingPathComponent(companion), options: .atomic)
    try FileManager.default.removeItem(at: incoming)
  }
}
