@testable import Lanterna
import Testing

/// A monitor and the fake tap behind it, so a test can drive the one and read
/// the other.
///
/// Named for what it holds rather than just `Fixture`: the presenter's own
/// fixture is shared across suites from `TestSupport`, and two things called
/// the same in one module, one of them shadowing the other only inside this
/// file, would read as the same thing.
@MainActor
private struct MonitorFixture {
    let tap: FakeEventTap
    let log: DiagnosticsLog
    let monitor: ModifierKeyMonitor
    /// How many times the monitor passed a release on to its owner.
    let releases: Counter

    @MainActor
    final class Counter {
        private(set) var count = 0
        func increment() {
            count += 1
        }
    }

    init(startSucceeds: Bool = true, hasPermission: Bool = true) {
        let tap = FakeEventTap()
        tap.startSucceeds = startSucceeds
        tap.hasPermission = hasPermission
        let log = DiagnosticsLog()
        let releases = Counter()
        monitor = ModifierKeyMonitor(
            tap: tap,
            onCommandRelease: { releases.increment() },
            writeLine: log.write
        )
        self.tap = tap
        self.log = log
        self.releases = releases
    }
}

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
        #expect(outcome.closesOnCommandRelease)
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

    /// Nothing recovers from the notice, so this line is the only trace a run
    /// leaves of it. Without it, a panel that started closing on a second press
    /// partway through a run would look like the monitor never started at all.
    @Test func theSystemSwitchingTheTapOffIsWrittenDown() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.start()
        fixture.tap.reportDisabledBySystem()
        #expect(
            fixture.log.lines.last
                == "the system switched the modifier monitor off; the panel now closes on a "
                + "second Cmd+Tab instead of when Command is released"
        )
    }

    @Test func startedSaysThePanelWillCloseOnTheRelease() {
        #expect(ModifierKeyMonitor.StartOutcome.started.closesOnCommandRelease)
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
        #expect(!outcome.closesOnCommandRelease)
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
