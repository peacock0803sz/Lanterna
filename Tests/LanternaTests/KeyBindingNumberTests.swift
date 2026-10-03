import Carbon.HIToolbox
@testable import Lanterna
import Testing

// MARK: - KeyBindingNumberTests

/// How the binding table answers number and reorder presses.
///
/// Digits with Command or Option held mean a row number only while the
/// number jump stands enabled; the same presses with it off keep their
/// long-standing meanings. Reorder presses win over plain arrows only
/// while their own switch stands enabled.
struct KeyBindingNumberTests {

  @Test
  func commandDigitMeansNumberWhileEnabled() {
    let keystroke = PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_3),
      modifiers: .command,
      isARepeat: false,
      characters: "3"
    )
    #expect(
      PanelKeyInput.action(for: keystroke, table: .defaults, numberJumpEnabled: true)
        == .numberDigit
    )
  }

  @Test
  func optionDigitMeansNumberWhileEnabled() {
    let keystroke = PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_3),
      modifiers: .option,
      isARepeat: false,
      characters: "3"
    )
    #expect(
      PanelKeyInput.action(for: keystroke, table: .defaults, numberJumpEnabled: true)
        == .numberDigit
    )
  }

  @Test
  func commandDigitKeepsItsMeaningWhileDisabled() {
    let keystroke = PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_3),
      modifiers: .command,
      isARepeat: false,
      characters: "3"
    )
    #expect(
      PanelKeyInput.action(for: keystroke, table: .defaults, numberJumpEnabled: false)
        == .filterText("3")
    )
  }

  @Test
  func remappedDigitKeyIsHonored() {
    let table = KeyBindingTable(keys: [
      .numberJump: [ResolvedKey(keyCode: UInt16(kVK_ANSI_5), modifiers: .option)]
    ])
    let honored = PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_5),
      modifiers: .option,
      isARepeat: false,
      characters: "5"
    )
    #expect(
      PanelKeyInput.action(for: honored, table: table, numberJumpEnabled: true)
        == .numberDigit
    )
    let moved = PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_5),
      modifiers: .command,
      isARepeat: false,
      characters: "5"
    )
    #expect(
      PanelKeyInput.action(for: moved, table: table, numberJumpEnabled: true)
        == .filterText("5")
    )
  }

  @Test
  func repeatingDigitIsAbsorbed() {
    let keystroke = PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_3),
      modifiers: .command,
      isARepeat: true,
      characters: "3"
    )
    #expect(
      PanelKeyInput.action(for: keystroke, table: .defaults, numberJumpEnabled: true)
        == .absorb
    )
  }

  @Test
  func reorderBeatsPlainArrowsWhileEnabled() {
    let up = PanelKeystroke(
      keyCode: UInt16(kVK_UpArrow),
      modifiers: [.command, .shift],
      isARepeat: false
    )
    #expect(
      PanelKeyInput.action(for: up, table: .defaults, reorderEnabled: true)
        == .moveRowUp
    )
    let down = PanelKeystroke(
      keyCode: UInt16(kVK_DownArrow),
      modifiers: [.option, .shift],
      isARepeat: false
    )
    #expect(
      PanelKeyInput.action(for: down, table: .defaults, reorderEnabled: true)
        == .moveRowDown
    )
  }

  @Test
  func reorderFallsBackToArrowsWhileDisabled() {
    let up = PanelKeystroke(
      keyCode: UInt16(kVK_UpArrow),
      modifiers: [.command, .shift],
      isARepeat: false
    )
    #expect(
      PanelKeyInput.action(for: up, table: .defaults, reorderEnabled: false)
        == .selectPrevious
    )
  }

}
