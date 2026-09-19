import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// Spelled as a press is made: a key, and whatever was held with it.
private func press(
    _ keyCode: Int,
    _ modifiers: NSEvent.ModifierFlags = [],
    repeating: Bool = false
) -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(keyCode), modifiers: modifiers, isARepeat: repeating)
}

struct PanelKeyInputTests {
    /// Every row but the full stop ignores the modifiers, and both ways round
    /// are said of each: the ordinary press comes with Command still down,
    /// and a run whose modifier monitor never started sees the same keys
    /// arrive bare once Command has been let go.
    @Test(arguments: [NSEvent.ModifierFlags(), .command])
    func theArrowsMoveTheSelectionWhateverIsHeldWithThem(modifiers: NSEvent.ModifierFlags) {
        #expect(PanelKeyInput.action(for: press(kVK_DownArrow, modifiers)) == .selectNext)
        #expect(PanelKeyInput.action(for: press(kVK_UpArrow, modifiers)) == .selectPrevious)
    }

    @Test(arguments: [NSEvent.ModifierFlags(), .command])
    func returnAndKeypadEnterCommitWhateverIsHeldWithThem(modifiers: NSEvent.ModifierFlags) {
        #expect(PanelKeyInput.action(for: press(kVK_Return, modifiers)) == .commit(.returnKey))
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_KeypadEnter, modifiers))
                == .commit(.keypadEnter)
        )
    }

    @Test(arguments: [NSEvent.ModifierFlags(), .command])
    func escapeCancelsWhateverIsHeldWithIt(modifiers: NSEvent.ModifierFlags) {
        #expect(PanelKeyInput.action(for: press(kVK_Escape, modifiers)) == .cancel(.escape))
    }

    /// The one key whose meaning turns on a modifier. A bare full stop is
    /// somebody typing, and typing must not cancel.
    @Test func theFullStopCancelsOnlyWithCommand() {
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_Period, .command))
                == .cancel(.commandPeriod)
        )
        #expect(PanelKeyInput.action(for: press(kVK_ANSI_Period)) == .absorb)
    }

    /// Keys nobody gave a meaning to still arrive, and are still swallowed.
    /// The panel takes the whole keyboard while it is up, so there is no such
    /// thing here as a key that carries on to somewhere else.
    @Test func keysWithNoMeaningAreAbsorbed() {
        #expect(PanelKeyInput.action(for: press(kVK_ANSI_A)) == .absorb)
        #expect(PanelKeyInput.action(for: press(kVK_ANSI_Q, .command)) == .absorb)
        #expect(PanelKeyInput.action(for: press(kVK_F1)) == .absorb)
        #expect(PanelKeyInput.action(for: press(kVK_Space)) == .absorb)
    }

    /// Holding an arrow down to run along a list is how a list is meant to be
    /// used, so the repeats it produces keep their meaning.
    @Test func theArrowsStillMoveWhenTheKeyboardIsRepeating() {
        #expect(
            PanelKeyInput.action(for: press(kVK_DownArrow, repeating: true)) == .selectNext
        )
        #expect(
            PanelKeyInput.action(for: press(kVK_UpArrow, repeating: true)) == .selectPrevious
        )
    }

    /// Committing or cancelling is done once by deciding to. A second one
    /// produced by leaning on the key would land on whatever the first left
    /// behind.
    @Test func committingAndCancellingDoNotRepeat() {
        #expect(PanelKeyInput.action(for: press(kVK_Return, repeating: true)) == .absorb)
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_KeypadEnter, repeating: true)) == .absorb
        )
        #expect(PanelKeyInput.action(for: press(kVK_Escape, repeating: true)) == .absorb)
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_Period, .command, repeating: true))
                == .absorb
        )
    }

    /// The name says the reason, because the rule reads like one that can be
    /// dropped: Carbon has claimed Cmd+Tab, so the argument goes, and a Tab
    /// can therefore never get here.
    ///
    /// Whether it can is not established. If it cannot, the rule costs one
    /// comparison; if it can, acting on it here as well as through Carbon
    /// moves the selection two rows for one press. Dropping the rule has to
    /// fail somewhere, and this is where.
    @Test func tabIsAbsorbedBecauseCarbonOwnsItAndTwoPathsWouldMoveTwoRows() {
        #expect(PanelKeyInput.action(for: press(kVK_Tab)) == .absorb)
        #expect(PanelKeyInput.action(for: press(kVK_Tab, .command)) == .absorb)
        #expect(PanelKeyInput.action(for: press(kVK_Tab, [.command, .shift])) == .absorb)
    }
}
