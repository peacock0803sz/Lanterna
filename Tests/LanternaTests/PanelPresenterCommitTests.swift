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
        Fixture(entryCount: entryCount, closesOnCommandRelease: true)
    }

    @Test func lettingGoWhileThePanelIsUpTakesItDownAndNamesTheRow() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        #expect(fixture.surface.dismissCount == 1)
        #expect(!fixture.surface.isPresented)

        let first = fixture.windows[0]
        #expect(
            fixture.log.lines.first(where: { $0.hasPrefix("committed ") })
                == "committed \(first.appName) — \(first.displayTitle) "
                + "(window \(first.id.windowID)) 4.8 ms after Command was released"
        )
    }

    /// One unit for one disappearance: the commit words its own, and the take
    /// words its pair, so the hiding wording must not also turn up — counting
    /// all three would see two events where the user saw one.
    @Test func aCommitIsTheOnlyLineThePanelGoingAwayProduces() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        #expect(fixture.log.lines.count == 3)
        #expect(fixture.log.lines.filter { $0.hasPrefix("panel hidden") }.isEmpty)
    }

    /// The figure is defined to run until the call that hides the panel comes
    /// back, and how quickly the panel goes is judged on it — so what the span
    /// covers has to be pinned by something, or it could quietly shrink to
    /// cover nothing and still read the same.
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
            fixture.log.lines.first(where: { $0.hasPrefix("committed ") })
                == "committed \(first.appName) — \(first.displayTitle) "
                + "(window \(first.id.windowID)) 9.6 ms after Command was released"
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
    /// last one took.
    ///
    /// What holds that is the commit's own `guard surface.isPresented`, which
    /// returns before the list or the choice is ever reached. This case does
    /// not hold either of them being given up with the panel, and no case
    /// can: nothing reads them while the panel is down, which is what the
    /// comment beside the line that clears the list already says.
    @Test func aSecondReleaseAfterACommitCommitsNothingFurther() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()
        let linesSoFar = fixture.log.lines

        fixture.presenter.handleCommandRelease()
        #expect(fixture.log.lines == linesSoFar)
        #expect(fixture.surface.dismissCount == 1)
    }

    /// The press moves the selection along now, and what this case holds is
    /// everything it must leave alone while doing so: the panel stays, no
    /// second one goes up, and nothing is written. Which row it lands on is
    /// held elsewhere, by the suite about the choice.
    ///
    /// Both combinations, because they walk opposite ways and a path that
    /// closed the panel for one of them would pass every case that only ever
    /// pressed the other.
    @Test(arguments: [HotkeyCombination.forward, .reverse])
    func withAMonitorRunningAFurtherPressDisturbsNothingButTheChoice(
        combination: HotkeyCombination
    ) {
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

    /// The monitor is the only thing that reports a release, so a run without
    /// one never makes this call. Pinned all the same: whether it is made is a
    /// property of how the delegate wires the two together, not of anything
    /// here, and the presenter is handed a way to ask whether a monitor is
    /// running precisely because that answer can change under it.
    ///
    /// All that is asked is that nothing be left wedged — the panel goes,
    /// one line says so, and the next press is answered as usual. Doing
    /// nothing instead is not asked for: this method can read no more of the
    /// situation than its caller already could, and a branch with no caller is
    /// a branch nothing keeps honest.
    @Test func withoutAMonitorAReleaseArrivingAnywayLeavesNothingWedged() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        let linesBefore = fixture.log.lines.count

        fixture.presenter.handleCommandRelease()

        #expect(fixture.surface.dismissCount == 1)
        #expect(!fixture.surface.isPresented)
        #expect(fixture.log.lines.count == linesBefore + 2)

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.count == 2)
        #expect(fixture.surface.isPresented)
    }

    /// A monitor that stops running partway through has to hand the closing
    /// back to the press. The release it was going to close on can no longer
    /// arrive, so a press still spent on the selection here would leave the
    /// panel's way out resting on the cancel keys alone — and those reach it
    /// only where it was granted key status.
    @Test func aMonitorThatStopsRunningHandsTheClosingBackToThePress() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        // The system has switched the tap off.
        fixture.monitorLiveness.isRunning = false
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(fixture.surface.dismissCount == 1)
        #expect(!fixture.surface.isPresented)
        #expect(fixture.log.lines.last == "panel hidden (Cmd+Tab)")
    }

    /// The two halves of one gesture come by different routes, so a quick tap
    /// can deliver them the other way round. A panel put up for a press whose
    /// Command has already gone is one the user has finished with, and the
    /// release that eventually clears it belongs to some unrelated keystroke,
    /// which would then be written down as a commit.
    @Test func aPressThatOutlivedItsReleaseIsTurnedAway() {
        let fixture = runningWithAMonitor()
        fixture.commandHold.isHeld = false

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(fixture.surface.presentedLists.isEmpty)
        #expect(!fixture.surface.isPresented)
        #expect(
            fixture.log.lines == [
                "turned away Cmd+Tab; Command was already up by the time the press arrived",
            ]
        )
    }

    /// The ordinary press, made with the key still down. Turning one of these
    /// away would cost every switch there is, so the check must not reach it.
    @Test func aPressMadeWithCommandDownStillPutsThePanelUp() {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.isPresented)
    }

    /// Without a monitor no release is being listened for, so none can have
    /// been lost and there is nothing to turn a press away for. The further
    /// press is what closes this panel, and it has to be able to open one.
    @Test func withoutAMonitorAPressIsAnsweredWhateverCommandIsDoing() {
        let fixture = Fixture(commandIsHeld: false)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.surface.isPresented)
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
        Fixture(
            store: WindowListStore(gather: fake.gather, writeLine: { _ in }),
            closesOnCommandRelease: true
        )
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

        let nothingToDo = Fixture(closesOnCommandRelease: true)
        nothingToDo.presenter.handleCommandRelease()

        #expect(calledOff.log.lines.count == 1)
        #expect(nothingToDo.log.lines.isEmpty)

        fake.finish()
        await settle()
        #expect(calledOff.surface.presentedLists.isEmpty)
    }
}
