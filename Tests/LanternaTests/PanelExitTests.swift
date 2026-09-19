import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// Spelled as a press is made, with Command still down, which is how these
/// keys arrive during the ordinary gesture.
private func press(_ keyCode: Int) -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(keyCode), modifiers: .command, isARepeat: false)
}

/// Leaving the panel without taking anything.
///
/// A file of its own for the reason `PanelPresenterCommitTests` is one: the
/// suites this would have joined are already long enough that adding to them
/// would put them over the file limit. The doubles come from `TestSupport`, so
/// every file driving the presenter drives the same fakes.
///
/// The wording of each line is pinned in `PanelExitMeasurementTests`, beside
/// the code that decides it. What is pinned here is that the right line comes
/// out of the right sequence of calls, exactly once, and that the lines a
/// cancellation must not produce stay absent.
@MainActor
struct PanelExitTests {
    private func runningWithAMonitor(entryCount: Int = 12) -> Fixture {
        Fixture(entryCount: entryCount, closesOnCommandRelease: true)
    }

    /// The whole of the story: the panel goes, one line says it was
    /// cancelled, and nothing says anything was taken.
    ///
    /// Worded as the line is. "Called off" is taken in this project — it is
    /// what a press given up on before its panel arrived says, and what an
    /// appearance abandoned for another application coming forward says — and
    /// a case further down exists to hold both of those absent from a
    /// cancellation.
    @Test func cancellingClosesThePanelAndCommitsNothing() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(fixture.presenter.handleKeyStroke(press(kVK_ANSI_Period)) == .absorbed)

        #expect(!fixture.surface.isPresented)
        #expect(fixture.surface.dismissCount == 1)
        #expect(fixture.log.lines.filter { $0.hasPrefix("cancelled ") }.count == 1)
        #expect(fixture.log.lines.filter { $0.hasPrefix("committed ") }.isEmpty)
    }

    /// Escape does the same thing and says so differently. The two are worded
    /// apart because which key arrived is the evidence for reading key codes
    /// rather than characters, and the system takes Cmd+Escape for itself on a
    /// stock machine — so a log that flattened them could not show which of
    /// the two a given run had available.
    @Test func escapeCancelsTheSameWayAndSaysWhichKeyDidIt() {
        let byPeriod = runningWithAMonitor()
        byPeriod.presenter.handleHotkey(.forward, deliveryDelay: nil)
        _ = byPeriod.presenter.handleKeyStroke(press(kVK_ANSI_Period))

        let byEscape = runningWithAMonitor()
        byEscape.presenter.handleHotkey(.forward, deliveryDelay: nil)
        _ = byEscape.presenter.handleKeyStroke(press(kVK_Escape))

        #expect(!byEscape.surface.isPresented)
        #expect(byPeriod.log.lines.last == "cancelled 4.8 ms after Cmd+Period")
        #expect(byEscape.log.lines.last == "cancelled 4.8 ms after Escape")
    }

    /// A bare full stop is somebody typing, and typing must not close the
    /// panel. Every other key this feature reads ignores its modifiers on
    /// purpose, so this is the one row where they matter — and the one that
    /// would be silently lost if the mapping were ever simplified.
    @Test func aFullStopWithoutCommandIsSwallowedRatherThanTakenAsACancellation() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        let afterTheAppearance = fixture.log.lines

        let bareFullStop = PanelKeystroke(
            keyCode: UInt16(kVK_ANSI_Period),
            modifiers: [],
            isARepeat: false
        )
        #expect(fixture.presenter.handleKeyStroke(bareFullStop) == .absorbed)

        #expect(fixture.surface.isPresented)
        #expect(fixture.log.lines == afterTheAppearance)
    }

    /// Cancelling an empty panel is cancelling. There is no row to decline
    /// either way, so a line that distinguished the two would be reporting a
    /// difference the user never made — unlike a commit, where an empty list
    /// is the reason nothing was taken and the line says so.
    @Test func anEmptyListCancelsWithTheSameLineAFullOneDoes() {
        let empty = runningWithAMonitor(entryCount: 0)
        empty.presenter.handleHotkey(.forward, deliveryDelay: nil)
        _ = empty.presenter.handleKeyStroke(press(kVK_ANSI_Period))

        let full = runningWithAMonitor()
        full.presenter.handleHotkey(.forward, deliveryDelay: nil)
        _ = full.presenter.handleKeyStroke(press(kVK_ANSI_Period))

        #expect(!empty.surface.isPresented)
        #expect(empty.log.lines.last == full.log.lines.last)
    }

    /// The gesture ends with Command coming up, and by then the panel is
    /// already gone. That release must write nothing: the user declined this
    /// appearance, and a line arriving afterwards would record a commit they
    /// spent a keystroke refusing.
    @Test func theReleaseThatFollowsACancellationWritesNothing() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        _ = fixture.presenter.handleKeyStroke(press(kVK_ANSI_Period))
        let afterTheCancellation = fixture.log.lines

        fixture.presenter.handleCommandRelease()

        #expect(fixture.log.lines == afterTheCancellation)
        #expect(fixture.surface.dismissCount == 1)
    }

    /// One disappearance, one line. The tidying-up wording must not also turn
    /// up: counting both would find two events where the user saw one, and
    /// the count of panels that closed is taken by matching these lines.
    @Test func aCancellationIsTheOnlyLineThePanelGoingAwayProduces() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        let afterTheAppearance = fixture.log.lines.count

        _ = fixture.presenter.handleKeyStroke(press(kVK_ANSI_Period))

        #expect(fixture.log.lines.count == afterTheAppearance + 1)
        #expect(fixture.log.lines.filter { $0.hasPrefix("panel hidden (") }.isEmpty)
        #expect(fixture.log.lines.filter { $0.hasPrefix("closed the panel") }.isEmpty)
    }

    /// Counting commits and counting cancellations must never pick up each
    /// other's lines. Taken from the log rather than from the wording, so that
    /// this holds for the lines the app actually writes and not only for the
    /// ones a wording test builds by hand.
    @Test func aCancelledLineIsNoPrefixOfACommittedOneNorTheOtherWayAbout() {
        let cancelled = runningWithAMonitor()
        cancelled.presenter.handleHotkey(.forward, deliveryDelay: nil)
        _ = cancelled.presenter.handleKeyStroke(press(kVK_ANSI_Period))

        let committed = runningWithAMonitor()
        committed.presenter.handleHotkey(.forward, deliveryDelay: nil)
        committed.presenter.handleCommandRelease()

        // Empty stands in for a line that never arrived, and fails every
        // assertion below rather than passing one of them by accident: the
        // empty string is a prefix of everything, including itself.
        let cancelledLine = cancelled.log.lines.last ?? ""
        let committedLine = committed.log.lines.last ?? ""

        #expect(cancelledLine.hasPrefix("cancelled "))
        #expect(committedLine.hasPrefix("committed "))
        #expect(!cancelledLine.hasPrefix(committedLine))
        #expect(!committedLine.hasPrefix(cancelledLine))
    }

    /// Cancelling gives the choice up with the panel. Without that, a second
    /// appearance would open on the row the declined one was left showing,
    /// and the first press of the next gesture would land somewhere the user
    /// never put it.
    @Test func thePanelAfterACancellationOpensOnItsOwnFirstRowAgain() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        _ = fixture.presenter.handleKeyStroke(press(kVK_DownArrow))
        _ = fixture.presenter.handleKeyStroke(press(kVK_DownArrow))
        _ = fixture.presenter.handleKeyStroke(press(kVK_ANSI_Period))

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(fixture.surface.presentedSelections.count == 2)
        #expect(fixture.surface.presentedSelections.last == fixture.windows.first?.id)
    }
}
