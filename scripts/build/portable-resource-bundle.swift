import Foundation

extension Foundation.Bundle {
  static let module: Bundle = {
    guard let resources = Bundle.main.resourceURL,
      let bundle = Bundle(url: resources.appendingPathComponent("FluidAudio_FluidAudio.bundle"))
    else {
      fatalError("FluidAudio resource bundle is missing from the application resources")
    }
    return bundle
  }()
}
