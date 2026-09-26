import AppKit
import Carbon.HIToolbox
import IOKit.hidsystem
@testable import Lanterna
import Testing

/// Spelled as a press is made: a key, and whatever was held with it.
private func press(
    _ keyCode: Int,
    _ modifiers: NSEvent.ModifierFlags = [],
    repeating: Bool = false,
    characters: String = ""
) -> PanelKeystroke {
    PanelKeystroke(
        keyCode: UInt16(keyCode), modifiers: modifiers, isARepeat: repeating,
        characters: characters
    )
}

/// The bit a real keyboard sets to say Command was held down on the left-hand
/// key rather than the right. It sits outside
/// `NSEvent.ModifierFlags.deviceIndependentFlagsMask`, which is what makes it
/// the thing to press a keystroke with when the narrowing is the claim.
private let leftCommandKey = NSEvent.ModifierFlags(
    rawValue: UInt(NX_DEVICELCMDKEYMASK)
)

struct PanelKeyInputTests {
    /// Every row but the full stop and the operations ignores the modifiers,
    /// and both ways round are said of each: the ordinary press comes with
    /// Command still down, and a run whose modifier monitor never started
    /// sees the same keys arrive bare once Command has been let go.
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

    /// Two presses that mean the same thing compare equal, whichever
    /// Command key was under the hand.
    ///
    /// Every other case here hands in flags that are already narrowed, so
    /// each of them would go on passing with the narrowing taken out of
    /// `PanelKeystroke.init` — the table asks whether Command is among the
    /// modifiers, and an extra bit beside it does not change that answer.
    /// What would break is quieter and lives one layer up: `PanelKeystroke`
    /// is `Equatable`, so the same Cmd+. made with the left Command and with
    /// the right would stop being the same keystroke. That is said here, in
    /// the form the promise takes, rather than only as a count of bits.
    @Test func theCommandKeyUsedDoesNotMakeItADifferentKeystroke() {
        let onTheLeftHandKey = press(kVK_ANSI_Period, [.command, leftCommandKey])
        #expect(onTheLeftHandKey == press(kVK_ANSI_Period, .command))
        #expect(onTheLeftHandKey.modifiers == .command)
        #expect(PanelKeyInput.action(for: onTheLeftHandKey) == .cancel(.commandPeriod))
    }

    /// Keys nobody gave a meaning to still arrive, and are still swallowed.
    /// The panel takes the whole keyboard while it is up, so there is no such
    /// thing here as a key that carries on to somewhere else.
    @Test func keysWithNoMeaningAreAbsorbed() {
        #expect(PanelKeyInput.action(for: press(kVK_ANSI_A)) == .absorb)
        #expect(PanelKeyInput.action(for: press(kVK_ANSI_S, .command)) == .absorb)
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

    /// Command combinations on the operation keys act on the chosen row
    /// instead of typing. The codes are what decide, so the input source
    /// does not matter.
    @Test func commandLettersOperateOnTheChosenRow() {
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_W, .command))
                == .windowOperation(.closeWindow)
        )
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_Q, .command))
                == .windowOperation(.quitApplication)
        )
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_H, .command))
                == .windowOperation(.hideApplication)
        )
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_M, .command))
                == .windowOperation(.minimizeWindow)
        )
    }

    /// The operations win over filtering: an operation key held with
    /// Command is an operation even where its letter would type, while any
    /// other Command letter still narrows.
    @Test func theOperationKeysWinOverFiltering() {
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_W, .command, characters: "w"))
                == .windowOperation(.closeWindow)
        )
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_S, .command, characters: "s"))
                == .filterText("s")
        )
    }

    /// Operating twice is not a thing anyone asks for. A second press from
    /// leaning on the key would land on whatever the first one left behind.
    @Test func operationsDoNotRepeat() {
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_W, .command, repeating: true))
                == .absorb
        )
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_Q, .command, repeating: true))
                == .absorb
        )
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_H, .command, repeating: true))
                == .absorb
        )
        #expect(
            PanelKeyInput.action(for: press(kVK_ANSI_M, .command, repeating: true))
                == .absorb
        )
    }

    /// On a run whose modifier monitor never started, Command is already up
    /// by the time a key arrives, so every keystroke comes in bare. The
    /// cases above already say each of these bare shapes one by one; this
    /// says them together, as the run sees them, so that dropping one of
    /// them reads as losing the run rather than as losing a row of a table.
    /// Moving along the list is the arrows' job on this run — Tab stays
    /// swallowed even here, because the two-path reason above does not turn
    /// on which modifiers are down.
    @Test func bareKeysStayUsableOnARunWithNoMonitor() {
        #expect(PanelKeyInput.action(for: press(kVK_DownArrow)) == .selectNext)
        #expect(PanelKeyInput.action(for: press(kVK_UpArrow)) == .selectPrevious)
        #expect(PanelKeyInput.action(for: press(kVK_Escape)) == .cancel(.escape))
        #expect(PanelKeyInput.action(for: press(kVK_Tab)) == .absorb)
    }
}
