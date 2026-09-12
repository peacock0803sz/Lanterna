@testable import Lanterna
import Testing

/// A monitor and the fake tap behind it, so a test can drive the one and read
/// the other.
@MainActor
private struct Fixture {
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
        let fixture = Fixture()
        #expect(fixture.monitor.start() == .started)
        #expect(fixture.tap.startCount == 1)
        #expect(fixture.tap.isEnabled)
    }

    /// A second attempt would leave two live taps on the run loop and report
    /// every release twice, so the first answer is the only one.
    @Test func startingAgainAttemptsNothingAndSaysWhatTheFirstAttemptDid() {
        let fixture = Fixture()
        let first = fixture.monitor.start()
        let second = fixture.monitor.start()
        #expect(first == second)
        #expect(fixture.tap.startCount == 1)
    }

    /// The whole point of the class from the app's side: a release the tap
    /// saw becomes a call on whoever owns the panel.
    @Test func aReleaseTheTapSawReachesTheOwner() {
        let fixture = Fixture()
        _ = fixture.monitor.start()
        fixture.tap.reportCommandRelease()
        #expect(fixture.releases.count == 1)
    }

    @Test func nothingReachesTheOwnerBeforeTheTapIsStarted() {
        let fixture = Fixture()
        fixture.tap.reportCommandRelease()
        #expect(fixture.releases.count == 0)
    }

    @Test func stoppingTakesTheTapDown() {
        let fixture = Fixture()
        _ = fixture.monitor.start()
        fixture.monitor.stop()
        #expect(fixture.tap.invalidateCount == 1)
        #expect(!fixture.tap.isEnabled)
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
    @Test func aRefusalWithoutPermissionSaysWhereToGrantIt() {
        let fixture = Fixture(startSucceeds: false, hasPermission: false)
        let outcome = fixture.monitor.start()
        #expect(outcome == .refused(hadPermission: false))
        #expect(outcome.summaryLine.contains("Privacy & Security > Input Monitoring"))
    }

    /// Sending someone to a setting that is already on would waste their time
    /// on the one failure the setting cannot fix.
    @Test func aRefusalWithPermissionDoesNotSendTheUserToSettings() {
        let fixture = Fixture(startSucceeds: false, hasPermission: true)
        let outcome = fixture.monitor.start()
        #expect(outcome == .refused(hadPermission: true))
        #expect(!outcome.summaryLine.contains("System Settings"))
        #expect(outcome.summaryLine.contains("even though input monitoring is granted"))
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
        let fixture = Fixture(startSucceeds: false, hasPermission: false)
        _ = fixture.monitor.start()
        fixture.monitor.stop()
        #expect(fixture.tap.invalidateCount == 1)
        #expect(fixture.releases.count == 0)
    }

    /// A refused run remembers the refusal rather than retrying on the next
    /// ask, which is what makes the permission decision a once-per-launch
    /// one.
    @Test func aRefusalIsNotRetried() {
        let fixture = Fixture(startSucceeds: false, hasPermission: false)
        _ = fixture.monitor.start()
        fixture.tap.startSucceeds = true
        #expect(fixture.monitor.start() == .refused(hadPermission: false))
        #expect(fixture.tap.startCount == 1)
    }
}
