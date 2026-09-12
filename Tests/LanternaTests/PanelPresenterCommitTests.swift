@testable import Lanterna
import Testing

/// What letting go of Command does to a panel.
///
/// A file of its own rather than more cases in `PanelPresenterTests`, which is
/// already long enough that adding these would put it over the file limit. The
/// doubles come from `TestSupport` so both files drive the same fakes.
///
/// Everything here starts from "the tap said Command was released". Which flag
/// changes deserve to be called that is settled below the seam, by
/// `SystemEventTapFlagsTests`, and nothing in this file could tell a wrong
/// answer there from a right one.
@MainActor
struct PanelPresenterCommitTests {
    /// A presenter wired the way a run with a working monitor wires it.
    private func runningWithAMonitor(entryCount: Int = 12) -> Fixture {
        let fixture = Fixture(entryCount: entryCount)
        fixture.presenter.closesOnCommandRelease = true
        return fixture
    }

    @Test func lettingGoWhileThePanelIsUpTakesItDownAndNamesTheRow() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        #expect(fixture.surface.dismissCount == 1)
        #expect(!fixture.surface.isPresented)

        let first = fixture.windows[0]
        #expect(
            fixture.log.lines.last
                == "committed \(first.appName) — \(first.displayTitle) "
                + "4.8 ms after Command was released"
        )
    }

    /// One line for one disappearance. The commit words its own, so the
    /// hiding wording must not also turn up — counting both would see two
    /// events where the user saw one.
    @Test func aCommitIsTheOnlyLineThePanelGoingAwayProduces() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        #expect(fixture.log.lines.count == 2)
        #expect(fixture.log.lines.filter { $0.hasPrefix("panel hidden") }.isEmpty)
    }

    /// The figure is defined to run until the call that hides the panel comes
    /// back, and the hundred-millisecond budget is judged on it — so what the
    /// span covers has to be pinned by something, or it could quietly shrink
    /// to cover nothing and still read the same.
    ///
    /// Nothing else in this file can tell the difference. Every reading of
    /// this clock costs one tick, so a figure taken after the dismissal and
    /// one taken before it both come out at a single tick. Charging the
    /// dismissal a tick of its own is what splits them: two ticks if the call
    /// is inside the span, one if it is not.
    @Test func theFigureCoversTheCallThatHidesThePanel() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.surface.onDismiss = { [clock = fixture.clock] in
            _ = clock.read()
        }

        fixture.presenter.handleCommandRelease()

        let first = fixture.windows[0]
        #expect(
            fixture.log.lines.last
                == "committed \(first.appName) — \(first.displayTitle) "
                + "9.6 ms after Command was released"
        )
    }

    /// An empty panel is still a panel, and hiding it is still part of the
    /// span. The wording differs from the case above; the span must not.
    @Test func anEmptyCommitIsMeasuredOverTheSameSpan() {
        let fixture = runningWithAMonitor(entryCount: 0)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.surface.onDismiss = { [clock = fixture.clock] in
            _ = clock.read()
        }

        fixture.presenter.handleCommandRelease()

        #expect(fixture.surface.dismissCount == 1)
        #expect(
            fixture.log.lines.last
                == "committed nothing 9.6 ms after Command was released (the list was empty)"
        )
    }

    @Test func aPanelWithNothingInItCommitsNothingAndSaysSo() {
        let fixture = runningWithAMonitor(entryCount: 0)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        #expect(fixture.surface.dismissCount == 1)
        #expect(
            fixture.log.lines.last
                == "committed nothing 4.8 ms after Command was released (the list was empty)"
        )
    }

    /// Every Cmd+C in the day ends with this call, and the panel is not up for
    /// any of them.
    @Test func lettingGoWithNoPanelUpDoesNothingAndSaysNothing() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleCommandRelease()

        #expect(fixture.surface.presentedLists.isEmpty)
        #expect(fixture.surface.dismissCount == 0)
        #expect(fixture.log.lines.isEmpty)
    }

    /// Twenty of them, because one quiet call proves less than a run of them:
    /// a counter or a stored instant that leaked would show up over many.
    @Test func aRunOfEverydayShortcutsLeavesNothingBehind() {
        let fixture = runningWithAMonitor()
        for _ in 0 ..< 20 {
            fixture.presenter.handleCommandRelease()
        }
        #expect(fixture.log.lines.isEmpty)

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.count == 1)
    }

    /// The panel is back up after a commit, which is the ordinary next press.
    @Test func aPressAfterACommitPutsThePanelBackUp() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(fixture.surface.presentedLists.count == 2)
        #expect(fixture.surface.isPresented)
    }

    /// A second release with nothing on screen must not commit the row the
    /// last one took, which is what clearing the selection with the panel
    /// buys.
    @Test func aSecondReleaseAfterACommitCommitsNothingFurther() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()
        let linesSoFar = fixture.log.lines

        fixture.presenter.handleCommandRelease()
        #expect(fixture.log.lines == linesSoFar)
        #expect(fixture.surface.dismissCount == 1)
    }

    /// The press is the one that would have moved the selection on, so with a
    /// monitor running it has to do nothing at all — not close the panel, and
    /// not put a second one up.
    @Test(arguments: [HotkeyCombination.forward, .reverse])
    func withAMonitorRunningAFurtherPressDoesNothing(combination: HotkeyCombination) {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        let linesSoFar = fixture.log.lines

        fixture.presenter.handleHotkey(combination, deliveryDelay: nil)

        #expect(fixture.surface.isPresented)
        #expect(fixture.surface.dismissCount == 0)
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.log.lines == linesSoFar)
    }

    /// Twenty presses with the key held, which is what holding Cmd and tapping
    /// Tab along a list looks like. None of them may close it.
    @Test func holdingCommandAndPressingOnLeavesThePanelUp() {
        let fixture = runningWithAMonitor()
        for _ in 0 ..< 20 {
            fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        }
        #expect(fixture.surface.isPresented)
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.dismissCount == 0)
    }

    /// Without a monitor there is nothing to report a release, so the press
    /// has to keep closing the panel exactly as it did before.
    @Test func withoutAMonitorThePressStillClosesThePanel() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(fixture.surface.dismissCount == 1)
        #expect(!fixture.surface.isPresented)
        #expect(fixture.log.lines.last == "panel hidden (Cmd+Tab)")
    }
}

/// Letting go before the panel ever arrived.
///
/// The window between launch and the first gathered list, which is the only
/// time a press has to wait — and so the only time a release can find one
/// waiting.
@MainActor
struct PanelPresenterCallOffTests {
    private func waitingForItsFirstList(_ fake: HeldGather) -> Fixture {
        let fixture = Fixture(
            store: WindowListStore(gather: fake.gather, writeLine: { _ in })
        )
        fixture.presenter.closesOnCommandRelease = true
        return fixture
    }

    @Test func aPressLetGoOfBeforeItsPanelIsCalledOff() async {
        let fake = HeldGather(entryCount: 4)
        let fixture = waitingForItsFirstList(fake)

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        await fake.waitUntilCalled()
        fixture.presenter.handleCommandRelease()

        fake.finish()
        await settle()

        #expect(fixture.surface.presentedLists.isEmpty)
        // Nothing was on screen, so nothing came off it.
        #expect(fixture.surface.dismissCount == 0)
        #expect(
            fixture.log.lines == [
                "press called off 4.8 ms after Command was released, "
                    + "before the panel appeared",
            ]
        )
    }

    /// The other half of what the span means. There is no panel to hide here,
    /// so the figure runs to the press being let go of and stops. Hanging a
    /// charge on the dismissal shows it is never paid: the figure stays at one
    /// tick, where a commit's is two.
    @Test func theFigureStopsShortWhenThereIsNoPanelToHide() async {
        let fake = HeldGather(entryCount: 4)
        let fixture = waitingForItsFirstList(fake)
        fixture.surface.onDismiss = { [clock = fixture.clock] in
            _ = clock.read()
        }

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        await fake.waitUntilCalled()
        fixture.presenter.handleCommandRelease()

        fake.finish()
        await settle()

        #expect(fixture.surface.dismissCount == 0)
        #expect(
            fixture.log.lines == [
                "press called off 4.8 ms after Command was released, "
                    + "before the panel appeared",
            ]
        )
    }

    /// A called-off press must not leave the next one waiting on a list that
    /// is never coming.
    @Test func aPressAfterACallOffIsAnsweredNormally() async {
        let fake = HeldGather(entryCount: 4)
        let fixture = waitingForItsFirstList(fake)

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        await fake.waitUntilCalled()
        fixture.presenter.handleCommandRelease()
        fake.finish()
        await settle()

        fixture.presenter.handleHotkey(.reverse, deliveryDelay: nil)
        await settle()

        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.isPresented)
        #expect(fixture.log.lines.count == 2)
    }

    /// The order of the two questions is what this pins. Were the panel asked
    /// about first, a press still on its way would take the quiet path, and
    /// the panel the user let go of would arrive anyway — over whatever they
    /// had turned to instead.
    @Test func aCallOffIsToldApartFromHavingNothingToDo() async {
        let fake = HeldGather(entryCount: 4)
        let calledOff = waitingForItsFirstList(fake)
        calledOff.presenter.handleHotkey(.forward, deliveryDelay: nil)
        await fake.waitUntilCalled()
        calledOff.presenter.handleCommandRelease()

        let nothingToDo = Fixture()
        nothingToDo.presenter.closesOnCommandRelease = true
        nothingToDo.presenter.handleCommandRelease()

        #expect(calledOff.log.lines.count == 1)
        #expect(nothingToDo.log.lines.isEmpty)

        fake.finish()
        await settle()
        #expect(calledOff.surface.presentedLists.isEmpty)
    }
}
