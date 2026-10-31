import CoreGraphics

// MARK: - FastSearchReleaseWatch

/// How the release watch reads whether a Fast Search key is still down.
///
/// The watch itself is `UnreportedReleaseWatch`, the one the switcher keys
/// use: only the question it asks differs. The tap reports the release in
/// the ordinary case; this catches the one it missed, so a panel is never
/// left up over a key nobody holds.
enum FastSearchReleaseWatch {

  // MARK: Internal

  /// Whether the key is down, asked of the session's keyboard state.
  ///
  /// The session state may not carry the bits that tell the two sides of
  /// Command or Option apart. Without them it is read side-blind: either
  /// key held keeps the panel up, which errs towards waiting for the tap.
  static func liveIsHeld(_ modifier: FastSearchModifier) -> Bool {
    if modifier == .capsLock {
      return CGEventSource.keyState(.combinedSessionState, key: escapeKeyCode)
    }
    let flags = CGEventSource.flagsState(.combinedSessionState)
    switch modifier {
    case .leftCommand,
         .rightCommand:
      return hasSides(flags, of: [.leftCommand, .rightCommand])
        ? modifier.isHeld(flags: flags, escapeHeld: false)
        : flags.contains(.maskCommand)

    case .leftOption,
         .rightOption:
      return hasSides(flags, of: [.leftOption, .rightOption])
        ? modifier.isHeld(flags: flags, escapeHeld: false)
        : flags.contains(.maskAlternate)

    case .fn,
         .capsLock:
      return modifier.isHeld(flags: flags, escapeHeld: false)
    }
  }

  /// Builds the watch for one search.
  ///
  /// It closes the panel only while the gate still reads the search as
  /// running: once the gate has moved on, the tap saw the release and its
  /// word is already on the way to the main actor, so closing here would
  /// throw away the commit that word is about to make.
  @MainActor
  static func make(
    modifier: FastSearchModifier,
    interval: Duration = UnreportedReleaseWatch.defaultInterval,
    isPanelUp: @escaping @MainActor () -> Bool,
    isHeld: @escaping @MainActor (FastSearchModifier) -> Bool,
    gateIsRunning: @escaping @MainActor () -> Bool,
    onUnreportedRelease: @escaping @MainActor () -> Void
  ) -> UnreportedReleaseWatch {
    UnreportedReleaseWatch(
      interval: interval,
      isPanelUp: isPanelUp,
      commandIsHeld: { isHeld(modifier) || !gateIsRunning() },
      onUnreportedRelease: onUnreportedRelease
    )
  }

  // MARK: Private

  private static let escapeKeyCode: CGKeyCode = 53

  private static func hasSides(_ flags: CGEventFlags, of sides: [FastSearchModifier]) -> Bool {
    sides.contains { $0.isHeld(flags: flags, escapeHeld: false) }
  }

}
