import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

// MARK: - PanelOptionReleaseTests

/// What letting go of Option does to a panel that is up.
///
/// A release under Command settles nothing and keeps any pending row
/// number for the Command release; any other release keeps the
/// long-standing path. Every release here is preceded by the tap-order
/// flags report, the way the hardware delivers it.
@MainActor
struct PanelOptionReleaseTests {

  // MARK: Internal

  @Test
  func optionReleaseUnderCommandKeepsThePanel() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.modifierFlagsChanged([.maskCommand, .maskAlternate])
    fixture.presenter.modifierFlagsChanged([.maskCommand])
    fixture.presenter.handleOptionRelease()

    #expect(fixture.surface.isPresented)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))

    fixture.presenter.modifierFlagsChanged([])
    fixture.presenter.handleCommandRelease()

    #expect(fixture.surface.dismissCount == 1)
    #expect(fixture.log.lines.contains(where: { $0.contains("after Command was released") }))
  }

  @Test
  func numberInputSurvivesOptionReleaseUnderCommand() {
    let fixture = Fixture(entryCount: 40, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.modifierFlagsChanged([.maskCommand, .maskAlternate])
    pressDigit(3, modifiers: [.command, .option], through: fixture)
    fixture.presenter.modifierFlagsChanged([.maskCommand])
    fixture.presenter.handleOptionRelease()
    pressDigit(4, modifiers: .command, through: fixture)
    fixture.presenter.modifierFlagsChanged([])
    fixture.presenter.handleCommandRelease()

    let named = fixture.windows[33]
    #expect(fixture.log.lines.contains(where: {
      $0.hasPrefix("committed ") && $0.contains(named.displayTitle)
    }))
    #expect(fixture.log.lines.contains(where: { $0.contains("after Command was released") }))
  }

  @Test
  func optionReleaseWhileFilteringKeepsThePanel() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    fixture.presenter.handleOptionRelease()

    #expect(fixture.surface.isPresented)

    fixture.presenter.modifierFlagsChanged([])
    fixture.presenter.handleOptionRelease()

    #expect(fixture.surface.isPresented)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  @Test
  func optionCommaHidesAndOpensSettingsWithoutCommitting() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    var opened = 0
    fixture.presenter.onOpenSettings = { opened += 1 }
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    fixture.presenter.modifierFlagsChanged([.maskAlternate])
    #expect(
      fixture.presenter.handleKeyStroke(PanelKeystroke(
        keyCode: UInt16(kVK_ANSI_Comma),
        modifiers: .option,
        isARepeat: false,
        characters: ","
      )) == .absorbed
    )
    #expect(!fixture.surface.isPresented)
    #expect(opened == 1)
    #expect(fixture.log.lines.count(where: { $0.hasPrefix("left for settings ") }) == 1)
    let afterLeaving = fixture.log.lines
    fixture.presenter.modifierFlagsChanged([])
    fixture.presenter.handleOptionRelease()
    #expect(fixture.log.lines == afterLeaving)
  }

  // MARK: Private

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
