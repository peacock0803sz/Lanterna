import Carbon.HIToolbox

// MARK: - SettingsKey

/// Which key opened the settings, so the line written can say so.
///
/// Kept apart for the reason the commit and cancel keys are: which physical
/// key arrived is the evidence for going by key code at all, and a log that
/// flattened them would throw that evidence away.
enum SettingsKey: Equatable, Sendable {
  case commandComma
  case optionComma
  /// Any other settings key, by physical position.
  case custom(UInt16)
}

extension PanelKeyInput {
  /// Which settings key arrived, for the line that says so.
  ///
  /// The default keys keep their names; anything else goes down by
  /// position, which is the same evidence in plainer words. Command is
  /// read first, so a comma pressed with both modifiers names Command.
  static func settingsKey(for keystroke: PanelKeystroke) -> SettingsKey {
    guard Int(keystroke.keyCode) == kVK_ANSI_Comma else {
      return .custom(keystroke.keyCode)
    }
    if keystroke.modifiers.contains(.command) {
      return .commandComma
    }
    if keystroke.modifiers.contains(.option) {
      return .optionComma
    }
    return .custom(keystroke.keyCode)
  }
}
