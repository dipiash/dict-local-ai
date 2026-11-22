import Synchronization

public final class RecognitionSession: Sendable {
  private let stopped = Mutex(false)
  public init() {}
  public func cancel() { stopped.withLock { $0 = true } }
  public var cancelled: Bool { stopped.withLock { $0 } }
}
