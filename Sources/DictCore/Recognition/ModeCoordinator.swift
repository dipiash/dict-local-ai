import Foundation

@MainActor
public final class ModeCoordinator {
  public enum Mode: Sendable { case dictation, file, meeting }
  public struct Lease: Equatable, Sendable {
    public let mode: Mode
    private let id = UUID()
    fileprivate init(mode: Mode) { self.mode = mode }
  }
  private var lease: Lease?
  public var active: Mode? { lease?.mode }
  public init() {}
  public func acquire(_ mode: Mode) -> Lease? {
    guard lease == nil else { return nil }
    let acquired = Lease(mode: mode)
    lease = acquired
    return acquired
  }
  public func release(_ completed: Lease?) {
    guard let completed, lease == completed else { return }
    lease = nil
  }
}
