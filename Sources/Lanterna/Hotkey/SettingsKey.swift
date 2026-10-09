import Carbon.HIToolbox

// MARK: - SettingsKey

/// Which key opened the settings, so the line written can say so.
///
/// Kept apart for the reason the commit and cancel keys are: which physical
/// key arrived is the evidence for going by key code at all, and a log that
/// flattened them would throw that evidence away.
enum SettingsKey: Equatable, Sendable {
  case commandComma
  /// A customized settings key, by physical position.
  case custom(UInt16)
}

extension PanelKeyInput {
  /// Which settings key arrived, for the line that says so.
  ///
  /// The long-standing key keeps its name; anything else goes down by
  /// position, which is the same evidence in plainer words.
  static func settingsKey(for keystroke: PanelKeystroke) -> SettingsKey {
    if Int(keystroke.keyCode) == kVK_ANSI_Comma, keystroke.modifiers.contains(.command) {
      .commandComma
    } else {
      .custom(keystroke.keyCode)
    }
  }
}
