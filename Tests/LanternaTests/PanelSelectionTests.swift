import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// Spelled as a press is made: a key, and whatever was held with it.
private func press(_ keyCode: Int) -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(keyCode), modifiers: .command, isARepeat: false)
}

/// The choice moving, seen from outside the presenter.
///
/// A file of its own for the reason `PanelPresenterCommitTests` is one: the
/// suites this would have joined are already long enough that adding to them
/// would put them over the file limit. The doubles come from `TestSupport`, so
/// every file driving the presenter drives the same fakes.
///
/// What the arithmetic does with a list of identities is settled in
/// `SelectionCursorTests`, which needs no panel at all. What is settled here
/// is everything that arithmetic cannot reach: that the presses arrive, that
/// the panel is told and told in the way that does not move it, that the row
/// a commit names is the row the panel was left highlighting, and that none
/// of it writes a line.
@MainActor
struct PanelSelectionTests {
    /// A presenter wired the way a run with a working monitor wires it, which
    /// is the only wiring in which a further press moves the choice.
    private func runningWithAMonitor(entryCount: Int = 12) -> Fixture {
        Fixture(entryCount: entryCount, closesOnCommandRelease: true)
    }

    @Test func aPanelOpensOnItsFirstRow() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.presentedSelections == [fixture.windows.first?.id])
        #expect(fixture.surface.shownSelections.isEmpty)
    }

    /// One press, one row. The count matters as much as the destination: a
    /// path that moved twice for one press would land on the right row for
    /// N = 1 and be wrong from there on, and one that moved not at all would
    /// pass every case where the answer happens to be the first row.
    @Test(arguments: [1, 2, 5, 9])
    func eachPressMovesTheChoiceExactlyOneRow(presses: Int) {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        for _ in 0 ..< presses {
            _ = fixture.presenter.handleKeyStroke(press(kVK_DownArrow))
        }
        #expect(fixture.surface.shownSelections.last == fixture.windows[presses].id)
        #expect(fixture.surface.shownSelections.count == presses)
    }

    /// The panel is redrawn and not put up again. Going through the entry
    /// that takes a list would resize the window and recentre it on every
    /// keystroke, and the only record of which entry was used is which of
    /// these two grew.
    @Test func movingTheChoiceRedrawsRatherThanShowingThePanelAgain() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        for _ in 0 ..< 4 {
            _ = fixture.presenter.handleKeyStroke(press(kVK_DownArrow))
        }
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.shownSelections.count == 4)
    }

    /// The up arrow is not a second implementation of the down arrow, and a
    /// presenter that wired both to the same step would pass every case above.
    @Test func theUpArrowGoesBackAndWrapsOntoTheLastRow() {
        let fixture = runningWithAMonitor(entryCount: 5)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        _ = fixture.presenter.handleKeyStroke(press(kVK_UpArrow))
        #expect(fixture.surface.shownSelections.last == fixture.windows[4].id)
    }

    /// Moving the choice is the one thing done many times in a single
    /// appearance. A line for each would bury the lines saying what became of
    /// the panel, and would break the reading that counts appearances and
    /// disappearances off this log.
    @Test func movingTheChoiceWritesNothingAtAll() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        let afterTheAppearance = fixture.log.lines
        for _ in 0 ..< 20 {
            _ = fixture.presenter.handleKeyStroke(press(kVK_DownArrow))
        }
        #expect(fixture.log.lines == afterTheAppearance)
    }

    /// The commit has to name where the choice ended up, not where it began.
    /// The panel drew one row and the line named another for as long as the
    /// two were worked out separately, and nothing could catch it while the
    /// choice could not move.
    @Test func aCommitNamesTheRowTheChoiceWasMovedTo() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        _ = fixture.presenter.handleKeyStroke(press(kVK_DownArrow))
        _ = fixture.presenter.handleKeyStroke(press(kVK_DownArrow))
        fixture.presenter.handleCommandRelease()

        let third = fixture.windows[2]
        #expect(fixture.surface.shownSelections.last == third.id)
        #expect(
            fixture.log.lines.last
                == "committed \(third.appName) — \(third.displayTitle) "
                + "(window \(third.id.windowID)) 4.8 ms after Command was released"
        )
    }

    /// Eighteen entries is where the sample list comes round on itself: the
    /// last row repeats the first row's application and title, and the two
    /// are told apart by nothing but their identity. A choice kept by name
    /// would commit the wrong one of them and read correctly in the log.
    @Test func twoRowsReadingAlikeAreStillCommittedApart() {
        let fixture = runningWithAMonitor(entryCount: 18)
        let first = fixture.windows[0]
        let last = fixture.windows[17]
        #expect(first.appName == last.appName)
        #expect(first.displayTitle == last.displayTitle)
        #expect(first.id != last.id)

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        _ = fixture.presenter.handleKeyStroke(press(kVK_UpArrow))
        fixture.presenter.handleCommandRelease()

        #expect(fixture.log.lines.last?.contains("(window \(last.id.windowID))") == true)
        #expect(fixture.log.lines.last?.contains("(window \(first.id.windowID))") == false)
    }

    /// A list with nothing to choose from and a list with nothing to choose
    /// between are the two shapes where the arithmetic has no move to make.
    /// The cursor's own suite says it leaves the choice alone; what it cannot
    /// say is that the press got that far. A presenter that fell over on an
    /// absent choice, or quietly stopped telling the panel, would look the
    /// same from there.
    @Test(arguments: [0, 1])
    func aListWithNoMoveToMakeStillTakesThePresses(entryCount: Int) {
        let fixture = runningWithAMonitor(entryCount: entryCount)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        _ = fixture.presenter.handleKeyStroke(press(kVK_DownArrow))
        _ = fixture.presenter.handleKeyStroke(press(kVK_UpArrow))

        let opened = fixture.windows.first?.id
        #expect(fixture.surface.shownSelections == [opened, opened])
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.isPresented)
    }
}

/// What a further press of the hotkey does to a panel that is already up.
///
/// Four states out of two questions, and the whole of the difference between
/// moving and closing lies in which of the four this is. The three that close
/// are staged here beside the one that does not, because what makes the
/// answer trustworthy is that the same press comes out differently — a suite
/// that only ever staged the moving one would pass against a presenter that
/// had forgotten how to close.
@MainActor
struct RepeatedPressStateTests {
    /// A monitor running and a watch started with the panel: the only state
    /// in which letting go of Command will close the panel, and so the only
    /// one in which the press is free to mean something else.
    @Test func aWatchedPanelTakesAFurtherPressAsAMove() {
        let fixture = Fixture(closesOnCommandRelease: true)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(fixture.surface.isPresented)
        #expect(fixture.surface.dismissCount == 0)
        #expect(fixture.surface.shownSelections == [fixture.windows[1].id])
    }

    /// The reversed combination walks the other way, which is the whole of
    /// what having two registered combinations buys while Command is held.
    @Test func theReversedCombinationWalksBackwards() {
        let fixture = Fixture(entryCount: 5, closesOnCommandRelease: true)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleHotkey(.reverse, deliveryDelay: nil)

        #expect(fixture.surface.shownSelections == [fixture.windows[4].id])
    }

    /// No monitor ever started, so no release is being listened for and the
    /// press is the panel's only way out.
    @Test func aPanelShownWithNoMonitorIsClosedByAFurtherPress() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(!fixture.surface.isPresented)
        #expect(fixture.surface.shownSelections.isEmpty)
        #expect(fixture.log.lines.last == "panel hidden (Cmd+Tab)")
    }

    /// The monitor was down when the panel went up, so this appearance was
    /// given no watch, and it has come back since. A monitor that comes back
    /// takes its idea of the modifiers from the keyboard as it finds it, so a
    /// Command let go meanwhile leaves it no release to report — the press
    /// still has to close the panel, and reading only "is a monitor running"
    /// would have it move the choice instead.
    @Test func aMonitorThatCameBackAfterwardsDoesNotMakeThePressAMove() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.monitorLiveness.isRunning = true
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(!fixture.surface.isPresented)
        #expect(fixture.surface.shownSelections.isEmpty)
        #expect(fixture.log.lines.last == "panel hidden (Cmd+Tab)")
    }

    /// The other way round: the watch is looking, and the monitor that was
    /// going to report the release has stopped. Reading only "is there a
    /// watch" would have this press move the choice and leave a panel with
    /// nothing left to close it.
    @Test func aMonitorThatStoppedAfterwardsLeavesTheClosingWithThePress() {
        let fixture = Fixture(closesOnCommandRelease: true)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.monitorLiveness.isRunning = false
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(!fixture.surface.isPresented)
        #expect(fixture.surface.shownSelections.isEmpty)
        #expect(fixture.log.lines.last == "panel hidden (Cmd+Tab)")
    }
}
