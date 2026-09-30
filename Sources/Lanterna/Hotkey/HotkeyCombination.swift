import AppKit
import Carbon.HIToolbox

// MARK: - HotkeyCombination

/// The key combinations the switcher takes over.
///
/// Carbon constants are read here, but no Carbon function is called, so the
/// whole type is testable. `HotkeyManager` does the registering.
enum HotkeyCombination: Sendable, CaseIterable, Hashable {
  case forward
  case reverse
  /// The filter invocation. Registered and diagnosed like the other two:
  /// `HotkeyManager` and the disable/restore discipline iterate `all`, so
  /// adding the case is what reaches them.
  case filter

  // MARK: Lifecycle

  /// Turns an identifier read off a press back into the combination it
  /// stands for, or `nil` for an identifier this app never handed out.
  init?(id: UInt32) {
    guard let match = Self.allCases.first(where: { $0.id == id }) else {
      return nil
    }
    self = match
  }

  // MARK: Internal

  /// Everything that gets registered. Registration is all-or-each: the two
  /// are registered separately and either can fail on its own.
  static var all: [HotkeyCombination] {
    allCases
  }

  /// Rides along on the `EventHotKeyID` and comes back on every press, which
  /// is how the handler tells the two apart. Non-zero, so a zeroed-out
  /// identifier cannot be mistaken for a real one.
  var id: UInt32 {
    switch self {
    case .forward: 1
    case .reverse: 2
    case .filter: 3
    }
  }

  var keyCode: UInt32 {
    switch self {
    case .forward,
         .reverse: UInt32(kVK_Tab)
    case .filter: UInt32(kVK_Space)
    }
  }

  var carbonModifiers: UInt32 {
    switch self {
    case .forward,
         .filter: UInt32(cmdKey)
    case .reverse: UInt32(cmdKey | shiftKey)
    }
  }

  /// How the combination is spelled in the diagnostics lines the manual
  /// acceptance checks grep for.
  var name: String {
    switch self {
    case .forward: "Cmd+Tab"
    case .reverse: "Shift+Cmd+Tab"
    case .filter: "Cmd+Space"
    }
  }
}

// MARK: - HotkeyBinding

/// One Carbon registration: which invocation it opens, and with what.
///
/// An action may hold several keys, so one combination can stand behind
/// several bindings. The event identifier carries both: the combination
/// in the high part and the key's slot in the low part, which is how a
/// press finds its way back without a lookup table anywhere else.
struct HotkeyBinding: Equatable, Sendable {

  // MARK: Internal

  /// The long-standing three bindings.
  static var defaults: [HotkeyBinding] {
    bindings(for: .defaults)
  }

  /// The invocation this key opens.
  let combination: HotkeyCombination
  /// Which of the action's keys this is, from zero.
  let slot: Int
  /// The physical key, for `RegisterEventHotKey`.
  let keyCode: UInt32
  /// The Carbon modifiers, for `RegisterEventHotKey`.
  let carbonModifiers: UInt32
  /// How diagnostics lines name it, spelled like the long-standing
  /// three: modifiers first, then the key.
  let name: String

  /// The identifier stamped on the registration. The low six bits
  /// carry the slot, so up to 64 keys fit behind one invocation.
  var eventID: UInt32 {
    combination.id * 64 + UInt32(slot)
  }

  /// One binding per key of every invocation action, in a fixed
  /// order: show, then reverse, then filter.
  static func bindings(for table: KeyBindingTable) -> [HotkeyBinding] {
    let actions: [(HotkeyCombination, KeyBindingAction)] = [
      (.forward, .show),
      (.reverse, .showReverse),
      (.filter, .showFilter),
    ]
    return actions.flatMap { combination, action in
      table[action].enumerated().map { slot, key in
        HotkeyBinding(
          combination: combination,
          slot: slot,
          keyCode: UInt32(key.keyCode),
          carbonModifiers: carbonModifiers(for: key.modifiers),
          name: key.displayName
        )
      }
    }
  }

  /// The combination behind a stamped identifier, or `nil` for one
  /// this app never handed out. Identifiers 1 through 3 keep their
  /// long-standing meaning; anything wider divides back down.
  static func combination(forEventID id: UInt32) -> HotkeyCombination? {
    if let legacy = HotkeyCombination(id: id) {
      return legacy
    }
    return HotkeyCombination.allCases.first { $0.id == id / 64 }
  }

  // MARK: Private

  /// Carbon's modifier word for narrowed flags. Only the four schema
  /// words arrive here, because resolution refuses anything else.
  private static func carbonModifiers(for flags: NSEvent.ModifierFlags) -> UInt32 {
    var modifiers: UInt32 = 0
    if flags.contains(.command) {
      modifiers |= UInt32(cmdKey)
    }
    if flags.contains(.control) {
      modifiers |= UInt32(controlKey)
    }
    if flags.contains(.option) {
      modifiers |= UInt32(optionKey)
    }
    if flags.contains(.shift) {
      modifiers |= UInt32(shiftKey)
    }
    return modifiers
  }

}
