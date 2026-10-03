import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

// MARK: - PanelPresenterNumberTests

/// What number presses do to a panel that is up.
///
/// Digits with Command or Option held name rows while the number jump
/// stands enabled; letting go commits the named row through the same
/// release path as ever. What is settled here is that wiring, and only
/// it — which physical keys count as digits is settled in
/// `DigitValueTests`, and the table answering them in
/// `KeyBindingNumberTests`.
@MainActor
struct PanelPresenterNumberTests {

  // MARK: Internal

  @Test
  func digitPreviewMovesTheChoice() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .command, through: fixture)

    #expect(fixture.presenter.selection.chosenID == fixture.windows[2].id)
  }

  @Test
  func optionDigitMovesTheChoiceTheSameWay() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .option, through: fixture)

    #expect(fixture.presenter.selection.chosenID == fixture.windows[2].id)
  }

  @Test
  func digitLeavesTheQueryAlone() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .command, through: fixture)

    #expect(!fixture.surface.updatedQueries.contains("3"))
  }

  @Test
  func invalidNumberKeepsTheChoice() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(9, modifiers: .command, through: fixture)
    pressDigit(9, modifiers: .command, through: fixture)
    let before = fixture.presenter.selection.chosenID

    #expect(fixture.presenter.selection.chosenID == before)
  }

  @Test
  func commandReleaseCommitsTheNamedRow() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .command, through: fixture)
    fixture.presenter.handleCommandRelease()

    #expect(fixture.surface.dismissCount == 1)
    let named = fixture.windows[2]
    #expect(fixture.log.lines.contains(where: {
      $0.hasPrefix("committed ") && $0.contains(named.displayTitle)
    }))
  }

  @Test
  func optionReleaseCommitsTheNamedRow() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .option, through: fixture)
    fixture.presenter.handleOptionRelease()

    #expect(fixture.surface.dismissCount == 1)
    let named = fixture.windows[2]
    #expect(fixture.log.lines.contains(where: {
      $0.hasPrefix("committed ") && $0.contains(named.displayTitle)
    }))
  }

  @Test
  func cancelAfterDigitsCommitsNothing() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .command, through: fixture)
    _ = fixture.presenter.handleKeyStroke(PanelKeystroke(
      keyCode: UInt16(kVK_Escape),
      modifiers: [],
      isARepeat: false
    ))

    #expect(!fixture.surface.isPresented)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  @Test
  func closedPanelIgnoresDigits() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    let disposition = fixture.presenter.handleKeyStroke(PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_3),
      modifiers: .command,
      isARepeat: false,
      characters: "3"
    ))

    #expect(disposition == .passedThrough)
    #expect(fixture.presenter.selection.chosenID == nil)
  }

  @Test
  func heldModifierShowsNumbersInDisplayOrder() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.modifierFlagsChanged([.maskCommand])

    #expect(fixture.surface.numberedRowOrders.last == fixture.windows.map(\.id))
  }

  @Test
  func releasedModifierTakesNumbersDown() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.modifierFlagsChanged([.maskCommand])
    fixture.presenter.modifierFlagsChanged([])

    #expect(fixture.surface.numberedRowOrders.last == [])
  }

  @Test
  func switchingTheJumpOffTakesNumbersDown() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.numberJump = false

    #expect(fixture.surface.numberedRowOrders.last == [])
  }

  // MARK: Private

  /// The key codes answering as digits on the main row, by value.
  private func keyCode(for digit: Int) -> UInt16 {
    switch digit {
    case 1: UInt16(kVK_ANSI_1)
    case 2: UInt16(kVK_ANSI_2)
    case 3: UInt16(kVK_ANSI_3)
    case 4: UInt16(kVK_ANSI_4)
    case 5: UInt16(kVK_ANSI_5)
    case 6: UInt16(kVK_ANSI_6)
    case 7: UInt16(kVK_ANSI_7)
    case 8: UInt16(kVK_ANSI_8)
    case 9: UInt16(kVK_ANSI_9)
    default: UInt16(kVK_ANSI_0)
    }
  }

  private func pressDigit(
    _ digit: Int,
    modifiers: NSEvent.ModifierFlags,
    through fixture: Fixture
  ) {
    _ = fixture.presenter.handleKeyStroke(PanelKeystroke(
      keyCode: keyCode(for: digit),
      modifiers: modifiers,
      isARepeat: false,
      characters: "\(digit)"
    ))
  }

}
