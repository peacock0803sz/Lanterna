import CoreGraphics

// MARK: - FastSearchModifier

/// A key that starts Fast Search while it is held.
///
/// The cases are in the order the settings show them and the settings file
/// lists them, and the raw values are the file's spellings.
enum FastSearchModifier: String, CaseIterable, Sendable {
  case fn
  /// The key System Settings remaps to Escape. Escape itself counts too:
  /// the events of the two cannot be told apart.
  case capsLock
  case leftCommand
  case rightCommand
  case leftOption
  case rightOption

  // MARK: Internal

  /// The name the settings and the diagnostics lines use.
  var displayName: String {
    switch self {
    case .fn: "Fn"
    case .capsLock: "Caps Lock"
    case .leftCommand: "Left Command"
    case .rightCommand: "Right Command"
    case .leftOption: "Left Option"
    case .rightOption: "Right Option"
    }
  }

  /// The one modifier held with nothing else but Shift, or nil.
  ///
  /// Control, a second modifier, or the other side's Command or Option
  /// makes it nil, so a chord the user meant for an app never starts a
  /// search. A Command or Option flag with no side bit is nil too: the
  /// side is what this feature selects on.
  nonisolated static func heldAlone(flags: CGEventFlags, escapeHeld: Bool) -> FastSearchModifier? {
    guard !flags.contains(.maskControl) else { return nil }
    if flags.contains(.maskCommand), held(in: flags, left: .leftCommand, right: .rightCommand) == nil {
      return nil
    }
    if flags.contains(.maskAlternate), held(in: flags, left: .leftOption, right: .rightOption) == nil {
      return nil
    }
    let held = allCases.filter { $0.isHeld(flags: flags, escapeHeld: escapeHeld) }
    return held.count == 1 ? held[0] : nil
  }

  /// Whether this modifier is down, read from its own bit alone.
  ///
  /// Escape never shows in the flags, so Caps Lock is read from whether
  /// the caller has seen Escape go down and not come up.
  nonisolated func isHeld(flags: CGEventFlags, escapeHeld: Bool) -> Bool {
    switch self {
    case .fn: flags.contains(.maskSecondaryFn)
    case .capsLock: escapeHeld
    case .leftCommand: flags.rawValue & Self.leftCommandBit != 0
    case .rightCommand: flags.rawValue & Self.rightCommandBit != 0
    case .leftOption: flags.rawValue & Self.leftOptionBit != 0
    case .rightOption: flags.rawValue & Self.rightOptionBit != 0
    }
  }

  // MARK: Private

  // The device-dependent bits that tell the two sides apart. Core Graphics
  // names only the side-blind masks; these come from IOKit's IOLLEvent.h.
  private static let leftCommandBit: UInt64 = 0x08
  private static let rightCommandBit: UInt64 = 0x10
  private static let leftOptionBit: UInt64 = 0x20
  private static let rightOptionBit: UInt64 = 0x40

  /// The side holding the key, or nil when neither side or both do.
  private nonisolated static func held(
    in flags: CGEventFlags,
    left: FastSearchModifier,
    right: FastSearchModifier
  ) -> FastSearchModifier? {
    switch (left.isHeld(flags: flags, escapeHeld: false), right.isHeld(flags: flags, escapeHeld: false)) {
    case (true, false): left
    case (false, true): right
    default: nil
    }
  }
}
