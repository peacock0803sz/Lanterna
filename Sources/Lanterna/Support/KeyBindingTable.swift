import AppKit
import Carbon.HIToolbox

// MARK: - BindingMode

/// How one action's keys are validated, and how hard they fight.
///
/// A static attribute of the action, never stored in the file: `global`
/// combinations reach across the system and must keep their modifiers,
/// `guarded` operations would fire while typing without them, and `bare`
/// panel keys work either way.
enum BindingMode: Equatable, Sendable {
  case global
  case guarded
  case bare
}

// MARK: - KeyBindingAction

/// Every action a key can drive, in the config file's words.
///
/// The raw values are the `keybindings` section's keys, so renaming one
/// renames the file format. The mode decides the validation from FR-012.
enum KeyBindingAction: String, CaseIterable, Equatable, Sendable {
  case show
  case showReverse
  case showFilter
  case next
  case previous
  case commit
  case cancel
  case deleteBackward
  case clearQuery
  case closeWindow
  case quitApplication
  case hideApplication
  case minimizeWindow

  // MARK: Internal

  var mode: BindingMode {
    switch self {
    case .show,
         .showReverse,
         .showFilter:
      .global
    case .closeWindow,
         .quitApplication,
         .hideApplication,
         .minimizeWindow:
      .guarded
    default:
      .bare
    }
  }
}

// MARK: - RawKeyBinding

/// One binding as the config file spells it, before validation.
struct RawKeyBinding: Equatable, Sendable {
  let keyCode: Int
  let modifiers: [String]
}

// MARK: - ResolvedKey

/// One binding the panel goes by: a physical key and narrowed modifiers.
struct ResolvedKey: Equatable, Hashable, Sendable {

  // MARK: Internal

  let keyCode: UInt16
  let modifiers: NSEvent.ModifierFlags

  /// The config file's words for these modifiers, in canonical order.
  /// Shared with the settings save, so the disk spells what the UI holds.
  var modifierWords: [String] {
    var words = [String]()
    if modifiers.contains(.command) {
      words.append("cmd")
    }
    if modifiers.contains(.control) {
      words.append("ctrl")
    }
    if modifiers.contains(.option) {
      words.append("opt")
    }
    if modifiers.contains(.shift) {
      words.append("shift")
    }
    return words
  }

  /// How lines and controls name it: modifiers first, then the key.
  /// Main-block ANSI keys take the US-layout keycap at that position,
  /// whatever the active layout types there; any key not named here
  /// falls back to `key N`.
  var displayName: String {
    var parts = [String]()
    if modifiers.contains(.shift) {
      parts.append("Shift")
    }
    if modifiers.contains(.control) {
      parts.append("Ctrl")
    }
    if modifiers.contains(.option) {
      parts.append("Opt")
    }
    if modifiers.contains(.command) {
      parts.append("Cmd")
    }
    switch Int(keyCode) {
    case kVK_Tab:
      parts.append("Tab")
    case kVK_Space:
      parts.append("Space")
    case kVK_Return:
      parts.append("Return")
    case kVK_ANSI_KeypadEnter:
      parts.append("Enter")
    case kVK_Escape:
      parts.append("Esc")
    case kVK_UpArrow:
      parts.append("Up")
    case kVK_DownArrow:
      parts.append("Down")
    case kVK_Delete:
      parts.append("Backspace")
    default:
      if let ansi = Self.ansiName(for: Int(keyCode)) {
        parts.append(ansi)
      } else {
        parts.append("key \(keyCode)")
      }
    }
    return parts.joined(separator: "+")
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(keyCode)
    hasher.combine(modifiers.rawValue)
  }

  // MARK: Private

  /// The US-layout keycap for a main-block (non-keypad) ANSI key code,
  /// or nil for any other key.
  /// Cases follow Events.h numeric order.
  private static func ansiName(for keyCode: Int) -> String? {
    switch keyCode {
    case kVK_ANSI_A:
      "A"
    case kVK_ANSI_S:
      "S"
    case kVK_ANSI_D:
      "D"
    case kVK_ANSI_F:
      "F"
    case kVK_ANSI_H:
      "H"
    case kVK_ANSI_G:
      "G"
    case kVK_ANSI_Z:
      "Z"
    case kVK_ANSI_X:
      "X"
    case kVK_ANSI_C:
      "C"
    case kVK_ANSI_V:
      "V"
    case kVK_ANSI_B:
      "B"
    case kVK_ANSI_Q:
      "Q"
    case kVK_ANSI_W:
      "W"
    case kVK_ANSI_E:
      "E"
    case kVK_ANSI_R:
      "R"
    case kVK_ANSI_Y:
      "Y"
    case kVK_ANSI_T:
      "T"
    case kVK_ANSI_1:
      "1"
    case kVK_ANSI_2:
      "2"
    case kVK_ANSI_3:
      "3"
    case kVK_ANSI_4:
      "4"
    case kVK_ANSI_6:
      "6"
    case kVK_ANSI_5:
      "5"
    case kVK_ANSI_Equal:
      "="
    case kVK_ANSI_9:
      "9"
    case kVK_ANSI_7:
      "7"
    case kVK_ANSI_Minus:
      "-"
    case kVK_ANSI_8:
      "8"
    case kVK_ANSI_0:
      "0"
    case kVK_ANSI_RightBracket:
      "]"
    case kVK_ANSI_O:
      "O"
    case kVK_ANSI_U:
      "U"
    case kVK_ANSI_LeftBracket:
      "["
    case kVK_ANSI_I:
      "I"
    case kVK_ANSI_P:
      "P"
    case kVK_ANSI_L:
      "L"
    case kVK_ANSI_J:
      "J"
    case kVK_ANSI_Quote:
      "'"
    case kVK_ANSI_K:
      "K"
    case kVK_ANSI_Semicolon:
      ";"
    case kVK_ANSI_Backslash:
      "\\"
    case kVK_ANSI_Comma:
      ","
    case kVK_ANSI_Slash:
      "/"
    case kVK_ANSI_N:
      "N"
    case kVK_ANSI_M:
      "M"
    case kVK_ANSI_Period:
      "."
    case kVK_ANSI_Grave:
      "`"
    default:
      nil
    }
  }

}

// MARK: - KeyBindingIssueReason

/// Why one entry did not survive resolution. The text for the diagnostics
/// line is built by the caller, which knows the losing and winning sides.
enum KeyBindingIssueReason: Equatable, Sendable {
  case invalid
  case conflict
}

// MARK: - KeyBindingIssue

/// One fallback and its reason, for the diagnostics lines.
struct KeyBindingIssue: Equatable, Sendable {
  let action: KeyBindingAction?
  let reason: KeyBindingIssueReason
  let detail: String

  /// The one launch line per fallback: what gave way, why, and that
  /// the default stands in. Worded here so the shape stays testable
  /// while the writing itself lives with the launch path.
  var diagnosticsLine: String {
    let reasonWord =
      switch reason {
      case .invalid:
        "invalid"
      case .conflict:
        "conflict"
      }
    return
      "config keybinding (\(action?.rawValue ?? "unknown") \(reasonWord): \(detail)); using default"
  }
}

// MARK: - KeyAssignmentRefusal

/// Why a pressed key cannot join a row. The duplicate case carries who
/// holds it, so the notice can name names.
enum KeyAssignmentRefusal: Equatable, Sendable {
  case needsModifiers
  case alreadyHeld
  case heldBy([KeyBindingAction])
}

// MARK: - KeyBindingTable

/// The resolved table: what each action answers to.
///
/// Built once at launch (and again on every settings save) so no press
/// ever pays for validation. Equality is by value, which is what makes
/// the table unit-testable without a window server.
struct KeyBindingTable: Equatable, Sendable {

  // MARK: Internal

  /// The long-standing behaviour, key for key.
  static var defaults: KeyBindingTable {
    KeyBindingTable(keys: [
      .show: [ResolvedKey(keyCode: UInt16(kVK_Tab), modifiers: .command)],
      .showReverse: [
        ResolvedKey(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
      ],
      .showFilter: [ResolvedKey(keyCode: UInt16(kVK_Space), modifiers: .command)],
      .next: [ResolvedKey(keyCode: UInt16(kVK_DownArrow), modifiers: [])],
      .previous: [ResolvedKey(keyCode: UInt16(kVK_UpArrow), modifiers: [])],
      .commit: [
        ResolvedKey(keyCode: UInt16(kVK_Return), modifiers: []),
        ResolvedKey(keyCode: UInt16(kVK_ANSI_KeypadEnter), modifiers: []),
      ],
      .cancel: [
        ResolvedKey(keyCode: UInt16(kVK_Escape), modifiers: []),
        ResolvedKey(keyCode: UInt16(kVK_ANSI_Period), modifiers: .command),
      ],
      .deleteBackward: [ResolvedKey(keyCode: UInt16(kVK_Delete), modifiers: [])],
      .clearQuery: [ResolvedKey(keyCode: UInt16(kVK_Escape), modifiers: [])],
      .closeWindow: [ResolvedKey(keyCode: UInt16(kVK_ANSI_W), modifiers: .command)],
      .quitApplication: [ResolvedKey(keyCode: UInt16(kVK_ANSI_Q), modifiers: .command)],
      .hideApplication: [ResolvedKey(keyCode: UInt16(kVK_ANSI_H), modifiers: .command)],
      .minimizeWindow: [ResolvedKey(keyCode: UInt16(kVK_ANSI_M), modifiers: .command)],
    ])
  }

  var keys: [KeyBindingAction: [ResolvedKey]]

  /// Whether the key may join the action's row of this table. Emptied
  /// rows read as their defaults, the way resolution reads them
  /// downstream. Nothing refused means allowed. The settings UI goes
  /// through here, so the rules stay testable without the window.
  static func refusal(
    assigning key: ResolvedKey,
    to action: KeyBindingAction,
    in table: KeyBindingTable
  ) -> KeyAssignmentRefusal? {
    guard allows(modifiers: key.modifiers, mode: action.mode) else {
      return .needsModifiers
    }
    let effective = table.fillingEmptiesWithDefaults()
    if effective[action].contains(key) {
      return .alreadyHeld
    }
    let holders = effective.holders(of: key, except: action)
    guard holders.isEmpty else {
      return .heldBy(holders)
    }
    return nil
  }

  /// Whether these modifiers may drive the mode at all, before any
  /// key is considered. Shared with the settings UI, so an invalid
  /// assignment is refused there rather than falling back here.
  static func allows(modifiers: NSEvent.ModifierFlags, mode: BindingMode) -> Bool {
    switch mode {
    case .global,
         .guarded:
      modifiers.contains(.command) || modifiers.contains(.control)
        || modifiers.contains(.option)

    case .bare:
      true
    }
  }

  subscript(_ action: KeyBindingAction) -> [ResolvedKey] {
    keys[action] ?? []
  }

  /// This table with emptied rows reading as their defaults.
  func fillingEmptiesWithDefaults() -> KeyBindingTable {
    var filled = self
    for action in KeyBindingAction.allCases where filled[action].isEmpty {
      filled.keys[action] = KeyBindingTable.defaults[action]
    }
    return filled
  }

  /// Actions already holding this key, except the action itself and
  /// the excused query-clear/cancel sharing.
  func holders(of key: ResolvedKey, except action: KeyBindingAction) -> [KeyBindingAction] {
    KeyBindingAction.allCases.filter { other in
      guard other != action else { return false }
      guard (keys[other] ?? []).contains(key) else { return false }
      return !KeyBindingResolver.isExcusedPair(action, other)
    }
  }

  /// Whether this press drives the action: the key sits on a bound
  /// position with the required modifiers held. A bare binding only
  /// answers a key that types nothing, so a letter keeps narrowing
  /// the list instead of triggering.
  func matches(_ keystroke: PanelKeystroke, action: KeyBindingAction) -> Bool {
    (keys[action] ?? []).contains { key in
      key.keyCode == keystroke.keyCode
        && key.modifiers.isSubset(of: keystroke.modifiers)
        && (!key.modifiers.isEmpty || !typesText(keystroke))
    }
  }

  // MARK: Private

  /// Whether the press would narrow the list rather than drive.
  ///
  /// Read here, where a row means filtering: going by key code keeps
  /// the table independent of the input source, and what the key made
  /// is only asked where filtering is at stake.
  private func typesText(_ keystroke: PanelKeystroke) -> Bool {
    WindowFilter.allowedText(keystroke.characters) != nil
  }

}
