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
            displayTitle: row.displayTitle,
            isMinimized: row.isMinimized
        )
    }

    /// Letting go of Command takes the highlighted row, and nothing else.
    @Test func aReleaseCommitTakesTheChosenRow() {
        let fixture = released()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        #expect(!fixture.surface.isPresented)
        #expect(fixture.switcher.targets == [expectedTarget(of: fixture.windows[0])])
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
        #expect(fixture.switcher.targets == [expectedTarget(of: fixture.windows[0])])
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
    /// figure, the same row named twice.
    @Test func aCommitWritesTheTakeAsTheCommitsPair() {
        let fixture = released()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        let lines = fixture.log.lines
        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("committed "))
        #expect(lines[2].hasPrefix("switched to "))
        #expect(lines[2].contains("(window \(fixture.windows[0].id.windowID))"))
    }

    /// A failed take is a pair too, naming the reason in fixed words.
    @Test func aFailedTakeWritesTheReasonAsTheCommitsPair() {
        let fixture = released()
        fixture.switcher.outcomes = [.failed(.windowGone)]
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        let lines = fixture.log.lines
        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("committed "))
        #expect(lines[2].hasPrefix("could not switch to "))
        #expect(lines[2].contains("(window gone)"))
    }

    /// The pair keeps the trigger's wording on both lines.
    @Test func thePairKeepsTheKeyCommitWording() {
        let fixture = released()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleKeyStroke(PanelKeystroke(
            keyCode: UInt16(kVK_Return), modifiers: .command, isARepeat: false
        ))

        let lines = fixture.log.lines
        #expect(lines.count == 3)
        #expect(lines[2].hasSuffix("after Return"))
    }
}
