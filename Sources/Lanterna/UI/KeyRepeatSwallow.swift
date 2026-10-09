import AppKit

/// Remembers the key that switched the panel into filtering, so its repeats
/// read as nothing rather than as filtering letters.
struct KeyRepeatSwallow: Equatable, Sendable {
  /// The key code to swallow repeats of, or nil when swallowing nothing.
  private(set) var heldKeyCode: UInt16?

  /// Remembers the key code of the switching press.
  mutating func hold(_ keyCode: UInt16) {
    heldKeyCode = keyCode
  }

  /// Whether this press is a swallowed repeat. A press that is not a repeat
  /// clears the memory and is never swallowed.
  mutating func swallows(_ keystroke: PanelKeystroke) -> Bool {
    guard keystroke.isARepeat else {
      heldKeyCode = nil
      return false
    }
    return keystroke.keyCode == heldKeyCode
  }

  /// Forgets any remembered key, at the start and the end of a panel.
  mutating func reset() {
    heldKeyCode = nil
  }
}
