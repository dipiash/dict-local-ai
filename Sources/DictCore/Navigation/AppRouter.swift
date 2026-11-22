public enum WorkspaceSection: String, CaseIterable, Sendable {
  case dictation, files, meeting, history, settings, about
}

public struct AppRouter: Equatable, Sendable {
  public enum Decision: Equatable, Sendable {
    case confirmationRequired
    case navigated(from: WorkspaceSection, to: WorkspaceSection)
  }

  public private(set) var selected: WorkspaceSection = .settings
  public private(set) var isOpen = false
  public private(set) var pendingSection: WorkspaceSection?

  public init() {}

  @discardableResult
  public mutating func request(
    _ section: WorkspaceSection, historyHasUnsavedEdits: Bool
  ) -> Decision {
    if UnsavedEditPolicy.requiresConfirmation(
      dirty: historyHasUnsavedEdits,
      changesContext: selected == .history && section != .history)
    {
      pendingSection = section
      return .confirmationRequired
    }
    return navigate(to: section)
  }

  @discardableResult
  public mutating func confirmPending() -> Decision? {
    guard let section = pendingSection else { return nil }
    pendingSection = nil
    return navigate(to: section)
  }

  public mutating func cancelPending() { pendingSection = nil }

  @discardableResult
  public mutating func reopen() -> Decision {
    let previous = selected
    if !isOpen { selected = .settings }
    isOpen = true
    return .navigated(from: previous, to: selected)
  }

  public mutating func close() { isOpen = false }

  private mutating func navigate(to section: WorkspaceSection) -> Decision {
    let previous = selected
    selected = section
    isOpen = true
    return .navigated(from: previous, to: section)
  }
}
