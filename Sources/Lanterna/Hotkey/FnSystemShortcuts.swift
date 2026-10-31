// MARK: - FnSystemShortcuts

/// The Fn letter combinations the system keeps for itself.
///
/// A Fast Search started from Fn would take these presses away from the
/// system, so when one of them is the first letter it goes to the system
/// instead and the search does not start. Later letters in a search that
/// is already running are the search's: the user is typing a query by then.
///
/// Fixed rather than read from System Settings: these are not entries in
/// the symbolic hotkey table the system exposes, and the list is the one
/// Apple's keyboard shortcuts page gives for the Globe key.
enum FnSystemShortcuts {

  // MARK: Internal

  /// Whether Fn with this letter is one the system answers. The letter is
  /// as the layout types it, so an uppercase one means Shift was held.
  static func contains(_ character: Character) -> Bool {
    letters.contains(character)
  }

  // MARK: Private

  /// Fn-A shows the Dock and Fn-Shift-A Apps, Fn-C Control Center,
  /// Fn-D dictation, Fn-E emoji, Fn-H the desktop, Fn-N notifications and
  /// Fn-Q a quick note.
  private static let letters: Set<Character> = ["a", "A", "c", "d", "e", "h", "n", "q"]

}
