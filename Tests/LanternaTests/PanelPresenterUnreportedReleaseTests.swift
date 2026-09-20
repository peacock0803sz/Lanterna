import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// Spelled as a press is made, with Command still down: this whole file is
/// about the gesture that is still under way when the tap stops reporting.
private func press(_ keyCode: Int) -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(keyCode), modifiers: .command, isARepeat: false)
}

/// The panel outliving a release that nothing reported.
///
/// A file of its own for the reason `PanelPresenterCommitTests` is one: the
/// suites these would have joined are already long enough that adding them
/// would put them over the file limit. The doubles come from `TestSupport`, so
/// every file driving the presenter drives the same fakes.
///
/// The hole being closed: a tap can stay enabled and stop being handed events,
/// and nothing about it then looks stopped. The release never arrives, so the
/// panel stays up, and a further press is turned away because a monitor still
/// reports itself as running — leaving a panel that nothing on the keyboard
/// can close, since it is non-activating and takes no keys of its own.
@MainActor
struct PanelPresenterUnreportedReleaseTests {
    /// A presenter wired the way a run with a working monitor wires it. The
    /// watch's interval is short by default here, so a look costs a
    /// millisecond rather than the real twentieth of a second.
    private func runningWithAMonitor() -> Fixture {
        Fixture(closesOnCommandRelease: true)
    }

    /// The whole point. Command goes up, nothing says so, and the panel still
    /// has to come down — with a line, because a panel that vanished without
    /// one could not be told from a panel that was never up.
    ///
    /// The press asks whether Command is held once; the ask after it is the
    /// watch's first look of its own. Waiting for that ask rather than for a
    /// span of time is what keeps this from turning on how busy the machine
    /// is. The time limit is not about slowness: a presenter that never
    /// started the watch would leave this waiting for an ask that never comes,
    /// and would hang rather than fail.
    @Test(.timeLimit(.minutes(1))) func aReleaseNothingReportedStillClosesThePanel() async {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        fixture.commandHold.isHeld = false
        await fixture.commandHold.waitUntilAsked(times: 2)
        await settle()

        let first = fixture.windows[0]
        #expect(fixture.surface.dismissCount == 1)
        #expect(!fixture.surface.isPresented)
        #expect(
            fixture.log.lines.last
                == "closed the panel showing \(first.appName) — \(first.displayTitle) "
                + "(window \(first.id.windowID)); "
                + "Command was let go and the tap never said so"
        )
    }

    /// The line names the row the panel was left highlighting, not the row it
    /// opened on. This is the fourth way a panel can go, and the only one of
    /// the four whose line is written outside the measurement type — so it is
    /// the one where the choice and the wording could drift apart unnoticed.
    ///
    /// The case above cannot catch that. It moves nothing, so the row it
    /// opened on and the row it was left showing are the same row, and an
    /// implementation that reached for either would write the same line.
    ///
    /// Both halves are asserted. That the moved-to row is named, and that the
    /// row it opened on is not — because the two share an application name
    /// and differ only in the identity, and it is the identity that the
    /// acceptance procedure counts to find rows taken by mistake.
    @Test(.timeLimit(.minutes(1)))
    func theLineNamesTheRowTheChoiceWasMovedTo() async {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.presenter.handleKeyStroke(press(kVK_DownArrow)) == .absorbed)
        #expect(fixture.presenter.handleKeyStroke(press(kVK_DownArrow)) == .absorbed)

        fixture.commandHold.isHeld = false
        await fixture.commandHold.waitUntilAsked(times: 2)
        await settle()

        let third = fixture.windows[2]
        let first = fixture.windows[0]
        #expect(
            fixture.log.lines.last
                == "closed the panel showing \(third.appName) — \(third.displayTitle) "
                + "(window \(third.id.windowID)); "
                + "Command was let go and the tap never said so"
        )
        #expect(fixture.log.lines.last?.contains("(window \(first.id.windowID))") == false)
    }

    /// Holding Command and tapping along the list is the ordinary gesture, and
    /// it is the one the looking must not cut short. Three looks with the key
    /// still down, and the panel is exactly as it was.
    ///
    /// Three rather than one: a check that fired on its second look, or on a
    /// counter it had let slip, would pass a single look and fail a run of
    /// them.
    @Test(.timeLimit(.minutes(1))) func aPanelStaysUpForAsLongAsCommandIsHeld() async {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        let linesSoFar = fixture.log.lines

        await fixture.commandHold.waitUntilAsked(times: 4)

        #expect(fixture.surface.isPresented)
        #expect(fixture.surface.dismissCount == 0)
        #expect(fixture.log.lines == linesSoFar)
    }

    /// One disappearance, one line. A reported release takes the panel down
    /// and stops the looking, so the watch must not write its own line over
    /// the top: counting both afterwards would find two events where the user
    /// saw one.
    ///
    /// A sleep rather than an awaited event, for the reason the store's loop
    /// tests sleep: what is pinned here is that nothing further happens, and
    /// there is no event to await for something that must not occur. Fifty
    /// times the interval is long enough that a watch still running would have
    /// looked many times over within it.
    @Test func aReportedReleaseLeavesTheLookingNothingToSay() async {
        let fixture = runningWithAMonitor()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()

        fixture.commandHold.isHeld = false
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fixture.surface.dismissCount == 1)
        #expect(fixture.log.lines.count == 2)
        #expect(fixture.log.lines.filter { $0.hasPrefix("closed the panel") }.isEmpty)
    }

    /// Without a monitor nothing looks at Command at all. No release is
    /// expected on such a run — the further press is what closes the panel —
    /// and a panel taken down for Command being up would vanish the moment it
    /// appeared, because a press made with the key already up is exactly how
    /// this run is worked.
    ///
    /// That nothing was asked is the sharp end of it: with no monitor the
    /// press never reaches the question either, so a single ask would mean a
    /// watch had started where none should.
    @Test func withoutAMonitorNothingLooksAtCommandAtAll() async {
        let fixture = Fixture(commandIsHeld: false)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        try? await Task.sleep(for: .milliseconds(50))

        #expect(fixture.surface.isPresented)
        #expect(fixture.commandHold.askCount == 0)

        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(!fixture.surface.isPresented)
        #expect(fixture.log.lines.last == "panel hidden (Cmd+Tab)")
    }

    /// The other direction of the same answer changing, and the dangerous one.
    /// A monitor can come back while a panel is already up, and the panel it
    /// finds there is one it was never watching: that panel went up on a run
    /// with nothing running, so no watch was started for it, and the monitor
    /// has no release left to report either — it takes its idea of the
    /// modifiers from the keyboard as it finds it, so a Command let go while
    /// it was down leaves no edge behind. The press is the whole of that
    /// panel's way out, and an answer that turned true afterwards must not
    /// take it away.
    ///
    /// Nothing looking is the premise here rather than the finding, which is
    /// what the untouched ask count says: a panel shown with no monitor is
    /// given no watch, and that is exactly what leaves the press carrying the
    /// closing on its own.
    @Test func aMonitorComingBackLeavesTheClosingWithThePress() {
        let fixture = Fixture()
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.isPresented)
        #expect(fixture.commandHold.askCount == 0)

        // The tap is back on underneath a panel that is already up.
        fixture.monitorLiveness.isRunning = true
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(fixture.surface.dismissCount == 1)
        #expect(!fixture.surface.isPresented)
        #expect(fixture.log.lines.last == "panel hidden (Cmd+Tab)")
    }
}

/// The looking on its own, away from anything it might be looking at.
///
/// Worth driving directly: through a presenter only the paths a presenter
/// takes can be reached, and what has to hold here — one report per panel, the
/// panel asked about afresh after every wait, stopping meaning stopped — is
/// about the loop rather than about the panel.
@MainActor
struct UnreportedReleaseWatchTests {
    /// The three questions wired to doubles that can answer them. The report
    /// goes into a log rather than a counter, so that how many there were and
    /// which they were are one reading.
    ///
    /// Every test here holds what this returns until its last line, as the
    /// presenter holds its own for as long as it lives. The loop keeps only a
    /// weak hold on the watch, so one let go of mid-look stops looking — and a
    /// test that had let go would see the same empty log as a test whose
    /// subject correctly said nothing.
    private func watch(
        panel surface: FakeSurface,
        command hold: CommandHold,
        reportingTo log: DiagnosticsLog
    ) -> UnreportedReleaseWatch {
        UnreportedReleaseWatch(
            interval: .milliseconds(1),
            isPanelUp: { [surface] in surface.isPresented },
            commandIsHeld: { [hold] in hold.read() },
            onUnreportedRelease: { [log] in log.write("found a release") }
        )
    }

    @Test(.timeLimit(.minutes(1))) func aPanelUpWithCommandOffIsReportedOnce() async {
        let surface = FakeSurface()
        surface.present(windows: [], selecting: nil)
        let hold = CommandHold(isHeld: false)
        let log = DiagnosticsLog()

        let watching = watch(panel: surface, command: hold, reportingTo: log)
        watching.start()
        await hold.waitUntilAsked(times: 1)
        await settle()

        #expect(log.lines == ["found a release"])
        watching.stop()
    }

    /// Starting again ends what was started before. Two loops over one panel
    /// would find one release twice, and the second would be reporting a panel
    /// that the first had already had taken down.
    ///
    /// The ask count is what carries the claim. A loop returns once it has
    /// reported, so one loop takes exactly one look; a second loop would take
    /// a look of its own and the count would say two. The line count is kept
    /// beside it to show that the loop which survived still does the job.
    ///
    /// Waiting for that look rather than for a span of time is the whole
    /// difference between this passing and this being a race. `Task.sleep` is
    /// free to come back well after the span it was given — the clock grants
    /// it tolerance — so a fixed wait for something that is meant to happen
    /// proves nothing when it has not happened yet.
    @Test(.timeLimit(.minutes(1))) func startingAgainReplacesTheLookingRatherThanAddingToIt() async {
        let surface = FakeSurface()
        surface.present(windows: [], selecting: nil)
        let hold = CommandHold(isHeld: false)
        let log = DiagnosticsLog()

        let watching = watch(panel: surface, command: hold, reportingTo: log)
        watching.start()
        watching.start()
        await hold.waitUntilAsked(times: 1)
        await settle()

        #expect(log.lines.count == 1)
        #expect(hold.askCount == 1)
        watching.stop()
    }

    /// Stopping lands in the wait, which is where the looking spends all of
    /// its time. Nothing having been asked is what shows it ended before the
    /// first look rather than after it.
    @Test func stoppingEndsTheLookingBeforeItAsksAnything() async {
        let surface = FakeSurface()
        surface.present(windows: [], selecting: nil)
        let hold = CommandHold(isHeld: false)
        let log = DiagnosticsLog()

        let watching = watch(panel: surface, command: hold, reportingTo: log)
        watching.start()
        watching.stop()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(log.lines.isEmpty)
        #expect(hold.askCount == 0)
    }

    /// The panel can go down while this is asleep — a commit, or the user
    /// turning to something else. Command is up by the time it wakes, so a
    /// look that did not ask about the panel first would report a release
    /// against a panel that had already gone.
    ///
    /// The first look, taken with the key still down, is what makes this a
    /// test of the panel question rather than of a loop that was never
    /// running: it proves the loop was going round before the panel went. With
    /// the loop known to be going and Command known to be up, nothing but the
    /// panel question can account for the silence.
    @Test(.timeLimit(.minutes(1))) func aPanelThatWentDownWhileItSleptIsNotReportedOn() async {
        let surface = FakeSurface()
        surface.present(windows: [], selecting: nil)
        let hold = CommandHold(isHeld: true)
        let log = DiagnosticsLog()

        let watching = watch(panel: surface, command: hold, reportingTo: log)
        watching.start()
        await hold.waitUntilAsked(times: 1)

        surface.dismiss()
        hold.isHeld = false
        try? await Task.sleep(for: .milliseconds(50))

        #expect(log.lines.isEmpty)
        watching.stop()
    }
}
