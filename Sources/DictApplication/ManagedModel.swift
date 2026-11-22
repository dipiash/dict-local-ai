public enum ManagedModel: String, CaseIterable, Identifiable, Sendable {
  case ultra
  case nemotron

  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .ultra: "Parakeet Ultra"
    case .nemotron: "Nemotron 3 · fast32 + fast128"
    }
  }
}
