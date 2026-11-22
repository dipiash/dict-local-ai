public enum UnsavedEditPolicy {
  public static func requiresConfirmation(dirty: Bool, changesContext: Bool) -> Bool {
    dirty && changesContext
  }
}
