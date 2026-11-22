import AppKit

struct Shortcut: Codable, Equatable, Sendable {
  var key: UInt16
  var modifiers: UInt64
  var label: String
  private static let modifierKeyNames: [UInt16: String] = [
    58: "shortcuts.left-option", 61: "shortcuts.right-option",
    59: "shortcuts.left-control", 62: "shortcuts.right-control",
    55: "shortcuts.left-command", 54: "shortcuts.right-command",
    56: "shortcuts.left-shift", 60: "shortcuts.right-shift",
  ]

  var displayLabel: String {
    if self == .hold { return L10n.text("shortcuts.default-hold") }
    guard let keyName = Self.modifierKeyNames[key] else { return label }
    let keys = label.components(separatedBy: " + ")
    return (Array(keys.dropLast()) + [L10n.text(keyName)]).joined(separator: " + ")
  }

  static func nameForModifierKey(_ key: UInt16) -> String? {
    modifierKeyNames[key].map { L10n.text($0) }
  }

  static func == (lhs: Shortcut, rhs: Shortcut) -> Bool {
    lhs.key == rhs.key && lhs.modifiers == rhs.modifiers
  }
  static let hold = Shortcut(
    key: 58, modifiers: CGEventFlags.maskSecondaryFn.rawValue, label: "Left Option + Fn")
  static let toggle = Shortcut(
    key: 49, modifiers: CGEventFlags.maskSecondaryFn.rawValue, label: "Fn + Space")
  static let modifierKeys: [UInt16: CGEventFlags] = [
    63: .maskSecondaryFn, 58: .maskAlternate, 61: .maskAlternate,
    59: .maskControl, 62: .maskControl, 55: .maskCommand, 54: .maskCommand, 56: .maskShift,
    60: .maskShift,
  ]
  static let mask: CGEventFlags = [
    .maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn,
  ]
}
