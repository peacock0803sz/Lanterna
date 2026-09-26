import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// What each way out takes.
///
/// The wording of each line is pinned beside the code that decides it. What
/// is pinned here is that a commit takes exactly the row it named — no other
/// row, and nothing on the ways out that are not commits — and that the take
/// happens after the panel is gone and before the line is written.
@MainActor
struct PanelExitSwitchTests {
    private func released() -> Fixture {
        Fixture(entryCount: 12, closesOnCommandRelease: true)
    }

    private func expectedTarget(of row: WindowItem) -> ActivationTarget {
        ActivationTarget(
            id: row.id,
            ownerProcessIdentifier: row.ownerProcessIdentifier,
            appName: row.appName,
            displayTitle: row.displayTitle
        )
    }

    /// Letting go of Command takes the highlighted row, and nothing else.
    @Test func aReleaseCommitTakesTheChosenRow() {
        let fixture = released()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        #expect(!fixture.surface.isPresented)
        #expect(fixture.switcher.targets == [expectedTarget(of: fixture.windows[1])])
        #expect(fixture.log.lines.filter { $0.hasPrefix("committed ") }.count == 1)
    }

    /// Return takes the same row through the other entrance, and says so in
    /// its own words. Which physical key arrived is the evidence for reading
    /// key codes rather than characters, so the two entrances must stay
    /// worded apart.
    @Test func aKeyCommitTakesTheSameRowWithItsOwnTrigger() {
        let fixture = released()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleKeyStroke(PanelKeystroke(
            keyCode: UInt16(kVK_Return), modifiers: .command, isARepeat: false
        ))

        #expect(!fixture.surface.isPresented)
        #expect(fixture.switcher.targets == [expectedTarget(of: fixture.windows[1])])
        #expect(fixture.log.lines.last?.contains("after Return") == true)
    }

    /// The release keeps its own wording too. A log that flattened the two
    /// could not show which entrance a given run took.
    @Test func aReleaseCommitKeepsTheReleaseWording() {
        let fixture = released()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        #expect(fixture.log.lines.last?.contains("after Command was released") == true)
    }

    /// Saying not this one takes nothing. Naming the highlighted row here
    /// would read as that window having been taken.
    @Test func aCancelTakesNothing() {
        let fixture = released()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleKeyStroke(PanelKeystroke(
            keyCode: UInt16(kVK_Escape), modifiers: .command, isARepeat: false
        ))

        #expect(!fixture.surface.isPresented)
        #expect(fixture.switcher.targets.isEmpty)
        #expect(fixture.log.lines.filter {
            $0.hasPrefix("switched to ") || $0.hasPrefix("could not switch to ")
        }.isEmpty)
    }

    /// An empty list commits the same way a full one does, except there is
    /// no row to take.
    @Test func anEmptyCommitTakesNothing() {
        let fixture = Fixture(entryCount: 0, closesOnCommandRelease: true)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        #expect(!fixture.surface.isPresented)
        #expect(fixture.switcher.targets.isEmpty)
        #expect(fixture.log.lines.filter { $0.hasPrefix("committed nothing") }.count == 1)
        #expect(fixture.log.lines.filter {
            $0.hasPrefix("switched to ") || $0.hasPrefix("could not switch to ")
        }.isEmpty)
    }

    /// One appearance takes at most once. A second commit down the same path
    /// finds the panel gone and turns away.
    @Test func aSecondCommitDownTheSamePathTakesNothingMore() {
        let fixture = released()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()
        fixture.presenter.handleCommandRelease()

        #expect(fixture.switcher.targets.count == 1)
    }

    /// The take is reported as the commit line's pair: adjacent lines, one
    /// figure, the same row named twice. Both lines are matched whole, so a
    /// wording drift on either side turns red here.
    @Test func aCommitWritesTheTakeAsTheCommitsPair() {
        let fixture = released()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        let row = fixture.windows[1]
        let lines = fixture.log.lines
        #expect(lines.count == 3)
        #expect(
            lines[1]
                == "committed \(row.appName) — \(row.displayTitle) "
                + "(window \(row.id.windowID)) 4.8 ms after Command was released"
        )
        #expect(
            lines[2]
                == "switched to \(row.appName) — \(row.displayTitle) "
                + "(window \(row.id.windowID)) 4.8 ms after Command was released"
        )
    }

    /// A failed take is a pair too, naming the reason in fixed words.
    @Test func aFailedTakeWritesTheReasonAsTheCommitsPair() {
        let fixture = released()
        fixture.switcher.outcomes = [.failed(.windowGone)]
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        let row = fixture.windows[1]
        let lines = fixture.log.lines
        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("committed "))
        #expect(
            lines[2]
                == "could not switch to \(row.appName) — \(row.displayTitle) "
                + "(window \(row.id.windowID)) (window gone) 4.8 ms after Command was released"
        )
    }

    /// The panel going takes its list and its choice with it, so neither
    /// can name a row for an appearance that never showed it.
    @Test func theListAndTheChoiceGoWithThePanel() {
        let fixture = released()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(!fixture.presenter.wayOut.presentedWindows.isEmpty)
        #expect(fixture.presenter.selection.chosenID != nil)
        fixture.presenter.handleKeyStroke(PanelKeystroke(
            keyCode: UInt16(kVK_ANSI_Period), modifiers: .command, isARepeat: false
        ))

        #expect(!fixture.surface.isPresented)
        #expect(fixture.presenter.wayOut.presentedWindows.isEmpty)
        #expect(fixture.presenter.selection.chosenID == nil)
    }

    /// The pair keeps the trigger's wording on both lines.
    @Test func thePairKeepsTheKeyCommitWording() {
        let fixture = released()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleKeyStroke(PanelKeystroke(
            keyCode: UInt16(kVK_Return), modifiers: .command, isARepeat: false
        ))

        let row = fixture.windows[1]
        let lines = fixture.log.lines
        #expect(lines.count == 3)
        #expect(
            lines[2]
                == "switched to \(row.appName) — \(row.displayTitle) "
                + "(window \(row.id.windowID)) 4.8 ms after Return"
        )
    }
}
