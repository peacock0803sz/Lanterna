@testable import Lanterna
import Testing

@MainActor
struct ModifierKeyMonitorTests {
    @Test func aTapTheSystemHandsOverIsAStart() {
        let fixture = MonitorFixture()
        #expect(fixture.monitor.start() == .started)
        #expect(fixture.tap.startCount == 1)
        #expect(fixture.tap.isEnabled)
    }

    /// A tap the system hands over is a start whatever the preflight said.
    ///
    /// This is the combination that tells the two readings apart: a machine
    /// where a tap can be made without the input monitoring grant. Asking the
    /// preflight as well as the return value would report such a run as
    /// refused while it sat there monitoring, and the panel would then be
    /// waiting on a release the presenter had been told would never come.
    @Test func aTapHandedOverWithoutTheGrantIsStillAStart() {
        let fixture = MonitorFixture(startSucceeds: true, hasPermission: false)
        let outcome = fixture.monitor.start()
        #expect(outcome == .started)
        #expect(outcome.producedATap)
        #expect(
            outcome.summaryLine
                == "modifier monitor started; the panel closes when Command is released"
        )
    }

    /// A second attempt would leave two live taps on the run loop and report
    /// every release twice, so the first answer is the only one.
    ///
    /// The tap is made to fail between the two calls so that returning the
    /// remembered answer is the only way to answer `.started` twice. Left
    /// succeeding, a monitor that had forgotten and attempted again would
    /// answer `.started` as well and the comparison would pass regardless.
    @Test func startingAgainAttemptsNothingAndSaysWhatTheFirstAttemptDid() {
        let fixture = MonitorFixture()
        let first = fixture.monitor.start()
        fixture.tap.startSucceeds = false
        #expect(first == .started)
        #expect(fixture.monitor.start() == first)
        #expect(fixture.tap.startCount == 1)
    }

    /// The whole point of the class from the app's side: a release the tap
    /// saw becomes a call on whoever owns the panel.
    @Test func aReleaseTheTapSawReachesTheOwner() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.start()
        fixture.tap.reportCommandRelease()
        #expect(fixture.releases.count == 1)
    }

    @Test func nothingReachesTheOwnerBeforeTheTapIsStarted() {
        let fixture = MonitorFixture()
        fixture.tap.reportCommandRelease()
        #expect(fixture.releases.count == 0)
    }

    @Test func stoppingTakesTheTapDown() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.start()
        fixture.monitor.stop()
        #expect(fixture.tap.invalidateCount == 1)
        #expect(!fixture.tap.isEnabled)
    }

    /// Taking the tap down keeps the outcome rather than forgetting it. What
    /// the monitor is holding is the answer to a question asked once a launch
    /// — whether this run has a monitor — and a `stop()` on the way out is not
    /// the run changing its mind. Clearing it there would let a later `start()`
    /// put a second tap on the run loop, which is the thing remembering exists
    /// to prevent.
    @Test func stoppingDoesNotMakeTheRunForgetHowItWent() {
        let fixture = MonitorFixture()
        let first = fixture.monitor.start()
        fixture.monitor.stop()
        #expect(fixture.monitor.start() == first)
        #expect(fixture.tap.startCount == 1)
    }

    /// Being told is the quick route back: the tap goes on again in the same
    /// turn the notice arrives, with no wait for the loop to come round.
    ///
    /// The line carries no figure, and that is the point of its wording. Being
    /// told is the moment it happened, so there is no span between going down
    /// and being noticed for a figure to cover.
    @Test func aNoticeFromTheSystemPutsTheTapStraightBack() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.start()
        fixture.tap.isEnabled = false

        fixture.tap.reportDisabledBySystem()

        #expect(fixture.tap.enableCount == 1)
        #expect(fixture.tap.isEnabled)
        #expect(
            fixture.log.lines.last == "modifier monitor was disabled by the system; re-enabled"
        )
    }

    /// The two numbers are chosen against each other and set apart, and this
    /// is the only thing holding them together. Lengthening the interval past
    /// the limit breaks no behaviour and fails nothing else in the suite: the
    /// checks still run, the recoveries still work, and the only casualty is
    /// how long a panel can sit there with nothing able to close it — which no
    /// other case measures.
    ///
    /// Under rather than under by some margin. How much room to leave is a
    /// judgement the interval's own doc makes and argues for; what must never
    /// be true is that a check comes round only after the panel has already
    /// outstayed the limit.
    @Test func theHealthCheckIntervalLeavesRoomUnderTheLimit() {
        #expect(
            ModifierKeyMonitor.defaultHealthCheckInterval
                < ModifierKeyMonitor.strandedPanelLimit
        )
    }

    /// The line the periodic stops write at launch, and the one monitor line
    /// whose only caller a test cannot reach: it is written from a private
    /// method of `AppDelegate`, inside a launch that claims hotkeys and can
    /// end the process. Pinning it where the words are made is what keeps it
    /// inside the net every other line here is held in.
    ///
    /// The figure as well as the wording. Whole seconds and no decimal point
    /// is what a reader greps for, and a period put through a locale-aware
    /// formatter would read differently on a machine set to another language.
    @Test func theAnnouncementOfThePeriodicStopsIsPinned() {
        #expect(
            ModifierKeyMonitor.periodicStopAnnouncement(every: .seconds(3))
                == "stopping the modifier monitor every 3 s (--stop-monitor-every)"
        )
    }

    @Test func startedSaysThePanelWillCloseOnTheRelease() {
        #expect(ModifierKeyMonitor.StartOutcome.started.producedATap)
        #expect(
            ModifierKeyMonitor.StartOutcome.started.summaryLine
                == "modifier monitor started; the panel closes when Command is released"
        )
    }
}

/// The run where the system would not hand a tap over.
///
/// Both refusals have to leave the app running with the second press closing
/// the panel. They are told apart only so the line can say whether opening
/// System Settings would help.
@MainActor
struct ModifierKeyMonitorFallbackTests {
    /// Pinned whole rather than by the part naming the setting. This line is
    /// the only thing a user in this state is handed, and the two pieces most
    /// easily lost are ones no fragment was watching: the instruction to
    /// restart, without which granting the permission does nothing for the run
    /// they are in, and the spaces where the literal is joined, which a
    /// fragment sitting inside one piece can never cross.
    @Test func aRefusalWithoutPermissionSaysWhereToGrantIt() {
        let fixture = MonitorFixture(startSucceeds: false, hasPermission: false)
        let outcome = fixture.monitor.start()
        #expect(outcome == .refused(hadPermission: false))
        #expect(
            outcome.summaryLine
                == "modifier monitor could not start; input monitoring is not granted, "
                + "so the panel closes on a second Cmd+Tab instead; grant it in "
                + "System Settings > Privacy & Security > Input Monitoring and restart the app"
        )
    }

    /// Sending someone to a setting that is already on would waste their time
    /// on the one failure the setting cannot fix.
    ///
    /// The absence of the settings path is asserted on its own as well as by
    /// the whole-line pin, so that anyone rewording this line has to delete
    /// that claim deliberately rather than paste a new string over it.
    @Test func aRefusalWithPermissionDoesNotSendTheUserToSettings() {
        let fixture = MonitorFixture(startSucceeds: false, hasPermission: true)
        let outcome = fixture.monitor.start()
        #expect(outcome == .refused(hadPermission: true))
        #expect(!outcome.summaryLine.contains("System Settings"))
        #expect(
            outcome.summaryLine
                == "modifier monitor could not start even though input monitoring is "
                + "granted; the panel closes on a second Cmd+Tab instead"
        )
    }

    /// Whichever refusal it was, the panel must still be closable, and the
    /// only thing left to close it is the second press.
    @Test(arguments: [true, false])
    func neitherRefusalClosesOnTheRelease(hadPermission: Bool) {
        let outcome = ModifierKeyMonitor.StartOutcome.refused(hadPermission: hadPermission)
        #expect(!outcome.producedATap)
        #expect(outcome.summaryLine.contains("closes on a second Cmd+Tab instead"))
    }

    /// Three lines, one of which is written every run. A reader grepping for
    /// one must not match another, and no line may be a prefix of another.
    @Test func theThreeStartLinesAreTellableApart() {
        let outcomes: [ModifierKeyMonitor.StartOutcome] = [
            .started,
            .refused(hadPermission: false),
            .refused(hadPermission: true),
        ]
        let lines = outcomes.map(\.summaryLine)
        #expect(Set(lines).count == 3)
        for line in lines {
            #expect(lines.filter { $0.hasPrefix(line) }.count == 1)
            #expect(!line.contains("\n"))
        }
    }

    /// A refusal leaves nothing behind, but shutdown does not know that and
    /// calls `stop()` on every run.
    @Test func stoppingAfterARefusalIsSafe() {
        let fixture = MonitorFixture(startSucceeds: false, hasPermission: false)
        _ = fixture.monitor.start()
        fixture.monitor.stop()
        #expect(fixture.tap.invalidateCount == 1)
        #expect(fixture.releases.count == 0)
    }

    /// A refused run remembers the refusal rather than retrying on the next
    /// ask, which is what makes the permission decision a once-per-launch
    /// one.
    @Test func aRefusalIsNotRetried() {
        let fixture = MonitorFixture(startSucceeds: false, hasPermission: false)
        _ = fixture.monitor.start()
        fixture.tap.startSucceeds = true
        #expect(fixture.monitor.start() == .refused(hadPermission: false))
        #expect(fixture.tap.startCount == 1)
    }
}
