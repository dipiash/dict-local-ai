// swift-tools-version: 6.0
import PackageDescription

#if os(macOS)
  let sqlitePkgConfig: String? = nil
#else
  let sqlitePkgConfig: String? = "sqlite3"
#endif

var targets: [Target] = [
  .systemLibrary(name: "CSQLite", pkgConfig: sqlitePkgConfig),
  .target(name: "DictCore"),
  .target(name: "DictApplication", dependencies: ["DictCore"]),
  .target(name: "DictStorage", dependencies: ["CSQLite", "DictCore", "DictApplication"]),
  .testTarget(name: "DictCoreTests", dependencies: ["DictCore"]),
  .testTarget(name: "DictApplicationTests", dependencies: ["DictCore", "DictApplication"]),
  .testTarget(
    name: "DictStorageTests", dependencies: ["DictCore", "DictApplication", "DictStorage"]),
]
var dependencies: [Package.Dependency] = []
var products: [Product] = [.library(name: "DictCore", targets: ["DictCore"])]
#if os(macOS)
  dependencies.append(
    .package(
      url: "https://github.com/FluidInference/FluidAudio.git",
      revision: "503b4bd1bbf7220882de39fe8ae6716aae4132da"))
  targets.append(
    .executableTarget(
      name: "DictLocalAI",
      dependencies: [
        "DictCore", "DictApplication", "DictStorage",
        .product(name: "FluidAudio", package: "FluidAudio"),
      ]))
  products.append(.executable(name: "DictLocalAI", targets: ["DictLocalAI"]))
  targets.append(
    .testTarget(name: "DictMacTests", dependencies: ["DictLocalAI", "DictApplication", "DictCore"]))
#endif
let package = Package(
  name: "DictLocalAI", platforms: [.macOS(.v15)],
  products: products, dependencies: dependencies, targets: targets, swiftLanguageModes: [.v6])
