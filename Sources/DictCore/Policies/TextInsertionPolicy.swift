public enum TextInsertionPolicy {
  public struct Traits {
    public let role: String
    public let secure: Bool
    public let enabled: Bool
    public let editable: Bool?
    public let selectedTextWritable: Bool
    public let selectionWritable: Bool
    public let focused: Bool

    public init(
      role: String, secure: Bool, enabled: Bool = true, editable: Bool? = nil,
      selectedTextWritable: Bool = false, selectionWritable: Bool = false,
      focused: Bool = false
    ) {
      self.role = role
      self.secure = secure
      self.enabled = enabled
      self.editable = editable
      self.selectedTextWritable = selectedTextWritable
      self.selectionWritable = selectionWritable
      self.focused = focused
    }
  }

  public static func accepts(_ traits: Traits) -> Bool {
    guard !traits.secure, traits.enabled, traits.editable != false else { return false }
    switch traits.role {
    case "AXTextField", "AXTextArea", "AXComboBox": return true
    case "AXGroup":
      return traits.editable == true
        && (traits.focused || traits.selectedTextWritable || traits.selectionWritable)
    case "AXWebArea":
      return traits.editable == true && traits.focused
    default: return false
    }
  }

  public static func prefersPaste(webContent: Bool, bundleIdentifier: String?) -> Bool {
    if webContent { return true }
    guard let identifier = bundleIdentifier else { return false }
    let browsers = [
      "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac",
      "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
      "org.chromium.Chromium", "com.kagi.kagimacOS",
    ]
    return browsers.contains { identifier == $0 || identifier.hasPrefix($0 + ".") }
  }

  public static func mayPaste(
    sameProcess: Bool, sameWindow: Bool, bothWindowsKnown: Bool, secure: Bool
  ) -> Bool {
    sameProcess && !secure && (!bothWindowsKnown || sameWindow)
  }

  public static func mayDeliver(
    sameProcess: Bool, sameElement: Bool, matchingIdentifier: Bool = false, eligible: Bool
  ) -> Bool {
    sameProcess && (sameElement || matchingIdentifier) && eligible
  }
}
