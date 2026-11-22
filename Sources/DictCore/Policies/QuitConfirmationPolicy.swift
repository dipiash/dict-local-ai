public struct QuitConfirmationPolicy: Sendable {
  public let preferredSection: WorkspaceSection?

  public init(
    fileRunning: Bool, fileUnsaved: Bool, meetingRunning: Bool, meetingUnsaved: Bool,
    dictationBusy: Bool
  ) {
    if meetingRunning || meetingUnsaved {
      preferredSection = .meeting
    } else if fileRunning || fileUnsaved {
      preferredSection = .files
    } else if dictationBusy {
      preferredSection = .dictation
    } else {
      preferredSection = nil
    }
  }

  public var requiresConfirmation: Bool { preferredSection != nil }
}
