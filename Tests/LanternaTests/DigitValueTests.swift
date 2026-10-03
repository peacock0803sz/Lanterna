import Carbon.HIToolbox
@testable import Lanterna
import Testing

// MARK: - DigitValueTests

/// Which physical keys answer as decimal digits, whatever the input
/// source holds. Going by key code keeps digits working across layouts
/// and sources, the way the rest of the binding table already does.
struct DigitValueTests {

  @Test
  func mainRowDigitsReadAsTheirValues() {
    let cases: [(Int, Int)] = [
      (kVK_ANSI_1, 1),
      (kVK_ANSI_2, 2),
      (kVK_ANSI_3, 3),
      (kVK_ANSI_4, 4),
      (kVK_ANSI_5, 5),
      (kVK_ANSI_6, 6),
      (kVK_ANSI_7, 7),
      (kVK_ANSI_8, 8),
      (kVK_ANSI_9, 9),
      (kVK_ANSI_0, 0),
    ]
    for (keyCode, expected) in cases {
      #expect(PanelKeyInput.digitValue(for: UInt16(keyCode)) == expected, "for key \(keyCode)")
    }
  }

  @Test
  func keypadDigitsReadAsTheirValues() {
    let cases: [(Int, Int)] = [
      (kVK_ANSI_Keypad1, 1),
      (kVK_ANSI_Keypad2, 2),
      (kVK_ANSI_Keypad3, 3),
      (kVK_ANSI_Keypad4, 4),
      (kVK_ANSI_Keypad5, 5),
      (kVK_ANSI_Keypad6, 6),
      (kVK_ANSI_Keypad7, 7),
      (kVK_ANSI_Keypad8, 8),
      (kVK_ANSI_Keypad9, 9),
      (kVK_ANSI_Keypad0, 0),
    ]
    for (keyCode, expected) in cases {
      #expect(PanelKeyInput.digitValue(for: UInt16(keyCode)) == expected, "for key \(keyCode)")
    }
  }

  @Test
  func otherKeysReadAsNoDigit() {
    for keyCode in [kVK_Return, kVK_Tab, kVK_UpArrow, kVK_ANSI_A, kVK_Space] {
      #expect(
        PanelKeyInput.digitValue(for: UInt16(keyCode)) == nil,
        "for key \(keyCode)"
      )
    }
  }

}
