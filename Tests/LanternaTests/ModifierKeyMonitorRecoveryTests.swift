@testable import Lanterna
import Testing

/// Putting a stopped tap back, by both routes.
///
/// A file of its own rather than more cases beside the starting ones, which
/// are about a decision made once a launch; these are about what happens for
/// the rest of the run. The fixture comes from `TestSupport` so both files
/// drive the same fake.
///
/// The checks are called by hand almost everywhere. Waiting out a real
/// interval would put the length of that interval into what the suite costs,
/// and would make every figure below depend on how busy the machine was. The
/// two cases about the loop itself are the exception, and they are written to
/// need only a few milliseconds.
@MainActor
struct ModifierKeyMonitorRecoveryTests {
    /// A tap found still delivering is left alone, and passed over without a
    /// word. A line every couple of seconds saying nothing had happened would,
    /// alongside the list's own pass, bury the lines that mean something.
    @Test func aTapStillDeliveringIsLeftAloneAndUnremarkedOn() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.start()

        fixture.monitor.checkHealth()

        #expect(fixture.tap.enableCount == 0)
        #expect(fixture.log.lines.isEmpty)
    }

    /// The route that does not depend on being told, which is the one the
    /// promise rests on: a stop nothing announced is found by asking, and the
    /// tap goes back on.
    ///
    /// The figure is how long the tap was out, measured from the last time it
    /// was seen delivering — here the start, one tick earlier.
    @Test func aTapFoundStoppedGoesBackOnWithTheFigureSaidOutLoud() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.start()
        fixture.tap.isEnabled = false

        fixture.monitor.checkHealth()

        #expect(fixture.tap.enableCount == 1)
        #expect(fixture.tap.isEnabled)
        #expect(
            fixture.log.lines.last
                == "modifier monitor was found disabled; re-enabled 4.8 ms after it went down"
        )
    }

    /// A tap that will not come back is the one state in which a panel can be
    /// left with nothing to close it, so this line is what a run in that state
    /// leaves behind. Repeated every check, it is the only machine-readable
    /// evidence that the trouble is still going on.
    @Test func aTapThatWillNotComeBackSaysSoRatherThanGoingQuiet() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.start()
        fixture.tap.enableSucceeds = false
        fixture.tap.isEnabled = false

        fixture.monitor.checkHealth()

        #expect(fixture.tap.enableCount == 1)
        #expect(!fixture.tap.isEnabled)
        #expect(
            fixture.log.lines.last
                == "modifier monitor was found disabled; could not re-enable it"
        )
    }

    /// Four lines say that the tap came back, or did not, and which route
    /// noticed. Somebody grepping for one must not match another, and none may
    /// be a prefix of another — the pairs share every word up to the last few,
    /// which is exactly where a prefix would hide.
    @Test func theFourRecoveryLinesAreTellableApart() {
        var lines: [String] = []
        for byNotice in [true, false] {
            for comesBack in [true, false] {
                let fixture = MonitorFixture()
                _ = fixture.monitor.start()
                fixture.tap.enableSucceeds = comesBack
                fixture.tap.isEnabled = false
                if byNotice {
                    fixture.tap.reportDisabledBySystem()
                } else {
                    fixture.monitor.checkHealth()
                }
                lines.append(fixture.log.lines.last ?? "")
            }
        }

        #expect(Set(lines).count == 4)
        for line in lines {
            #expect(lines.filter { $0.hasPrefix(line) }.count == 1)
            #expect(!line.contains("\n"))
        }
    }

    /// Whether the tap is out for five seconds or not is judged on this figure
    /// alone, so what it is measured from has to be one thing and not three.
    /// Left to taste it could as easily run from the launch, from the last
    /// wake-up, or from the last time the tap came back, and three readings of
    /// three different spans cannot be compared with each other.
    ///
    /// One tick is the right answer in all three, and each wrong origin gives
    /// a different one: from the launch the second case would read 9.6 and the
    /// third 14.4, and from the check before it the third would read 9.6.
    @Test func theFigureRunsFromTheLastTimeTheTapWasSeenDelivering() {
        // Nothing seen enabled yet but the start itself.
        let fromTheStart = MonitorFixture()
        _ = fromTheStart.monitor.start()
        fromTheStart.tap.isEnabled = false
        fromTheStart.monitor.checkHealth()
        #expect(fromTheStart.log.lines.last == Self.foundDisabled("4.8"))

        // A check saw it enabled in between, so that check is the origin.
        let fromACheck = MonitorFixture()
        _ = fromACheck.monitor.start()
        fromACheck.monitor.checkHealth()
        fromACheck.tap.isEnabled = false
        fromACheck.monitor.checkHealth()
        #expect(fromACheck.log.lines.last == Self.foundDisabled("4.8"))

        // It already came back once, so that recovery is the origin.
        let fromARecovery = MonitorFixture()
        _ = fromARecovery.monitor.start()
        fromARecovery.tap.isEnabled = false
        fromARecovery.monitor.checkHealth()
        fromARecovery.tap.isEnabled = false
        fromARecovery.monitor.checkHealth()
        #expect(fromARecovery.log.lines.last == Self.foundDisabled("4.8"))
    }

    /// A developer log line has to read the same on every machine, whatever
    /// language it is set to. The step is chosen to be big enough to need a
    /// thousands separator: a number put through a locale-aware formatter
    /// would come out as `1,234.0` here and `1.234,0` elsewhere, and either
    /// would break a reader matching on the wording.
    @Test func theFigureReadsTheSameInEveryLanguage() {
        let fixture = MonitorFixture(step: .milliseconds(1234))
        _ = fixture.monitor.start()
        fixture.tap.isEnabled = false

        fixture.monitor.checkHealth()

        #expect(fixture.log.lines.last == Self.foundDisabled("1234.0"))
    }

    /// The stop a developer asks for, and the whole reason it is worth having:
    /// it announces itself to nobody, so the told route cannot see it and the
    /// asking is left to find it. That is the route the promise rests on, and
    /// this is the only way to put a real tap into the state that exercises
    /// it.
    @Test func aStopAskedForAnnouncesItselfToNobodyAndIsFoundByAsking() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.start()

        fixture.monitor.stopOnPurpose()

        #expect(!fixture.tap.isEnabled)
        #expect(fixture.tap.enableCount == 0)
        #expect(
            fixture.log.lines.last
                == "modifier monitor stopped on purpose (--stop-monitor-every)"
        )

        fixture.monitor.checkHealth()

        #expect(fixture.tap.enableCount == 1)
        #expect(fixture.tap.isEnabled)
        #expect(fixture.log.lines.last == Self.foundDisabled("4.8"))
    }

    /// The loop, driven for real rather than by hand — one of the two cases
    /// here that do. Without it, a `start()` that made no timer at all would
    /// pass every other case in this file.
    ///
    /// The time limit is not about slowness: what is awaited here is an ask
    /// the monitor is free to stop making, so a run that made no timer would
    /// park on it for ever and hang the suite rather than fail it.
    @Test(.timeLimit(.minutes(1))) func aStartedRunAsksWithoutWaitingToBeAsked() async {
        let fixture = MonitorFixture(healthCheckInterval: .milliseconds(1))
        _ = fixture.monitor.start()
        fixture.tap.isEnabled = false

        await fixture.tap.waitUntilAsked(times: 1)

        #expect(fixture.tap.enableCount == 1)
        #expect(fixture.tap.isEnabled)
    }

    /// The case above proves a timer fired once. This one proves there is a
    /// loop behind it, which is what the class promises: a
    /// `startHealthChecks()` cut down to one sleep and one check passes every
    /// other case in this file, and would leave a run asking after its tap
    /// once and then never again.
    ///
    /// The tap is held so that it cannot come back, because that is what
    /// leaves every turn something to do — one that came back would be found
    /// delivering on the next turn and asked about no further, and the count
    /// would stop at one for a reason that has nothing to do with the loop.
    /// It is also the state the repetition matters most in: a tap that will
    /// not return is the one a panel can be stranded by, and the line each
    /// turn writes is the only evidence that the trouble is still going on.
    ///
    /// Three turns for the reason the store's loop asks for three: a check
    /// that fired on its second turn, or on a count it had let slip, would
    /// pass a single turn and fail a run of them. At or above rather than
    /// exactly, because the loop is not stopped until after the wait and a
    /// further turn may land in between.
    ///
    /// The time limit is not about slowness: a loop reduced to a single pass
    /// would wait here for ever rather than fail.
    @Test(.timeLimit(.minutes(1))) func theAskingKeepsGoingRatherThanHappeningOnce() async {
        let fixture = MonitorFixture(healthCheckInterval: .milliseconds(1))
        _ = fixture.monitor.start()
        fixture.tap.enableSucceeds = false
        fixture.tap.isEnabled = false

        await fixture.tap.waitUntilAsked(times: 3)
        fixture.monitor.stop()

        #expect(fixture.tap.enableCount >= 3)
    }

    /// A refused run has no tap to ask about, so it must make no timer. One
    /// that did would wake an otherwise idle process every couple of seconds
    /// for the rest of its life, to ask a question with no subject.
    ///
    /// The time limit is not about slowness: the wait below is measured
    /// against a second monitor's loop rather than against the clock, so a
    /// `start()` that made no timer for either of them would leave this parked
    /// on an ask that never comes, hanging the suite instead of failing it.
    @Test(.timeLimit(.minutes(1))) func aRefusedRunNeverAsksAboutATapItNeverGot() async {
        let fixture = MonitorFixture(startSucceeds: false, healthCheckInterval: .milliseconds(1))
        #expect(fixture.monitor.start() == .refused(hadPermission: true))
        fixture.tap.isEnabled = false

        await Self.waitOutATurn()

        #expect(fixture.tap.enableCount == 0)
        #expect(fixture.log.lines.isEmpty)
    }

    /// Shutting down ends the asking. A loop left running would go on putting
    /// a tap back that the same call had just thrown away.
    ///
    /// The time limit is for the yardstick rather than for the subject: this
    /// waits on a loop belonging to another monitor, and a run in which no
    /// loop starts at all would strand the wait rather than reach the reading
    /// below.
    @Test(.timeLimit(.minutes(1))) func stoppingEndsTheAsking() async {
        let fixture = MonitorFixture(healthCheckInterval: .milliseconds(1))
        _ = fixture.monitor.start()
        fixture.monitor.stop()
        fixture.tap.isEnabled = false

        await Self.waitOutATurn()

        #expect(fixture.tap.enableCount == 0)
    }

    /// A shutdown must leave no alarm behind. The tap goes down first and the
    /// loop is cancelled second, so a turn already past its sleep arrives
    /// after the tap has gone — cancelling raises a flag rather than calling
    /// back a turn the actor has already been handed. A check running then
    /// would find no tap, fail to put one back, and write the line that says a
    /// panel is stuck with nothing able to close it: the one line a clean exit
    /// must never produce, because nothing in the log would tell it apart from
    /// the real thing.
    ///
    /// Driven by hand rather than by racing a timer, and the stronger test for
    /// it: what has to hold is that a check arriving after a stop writes
    /// nothing, whichever road it came by, and the road the race takes is only
    /// one of the two.
    ///
    /// Nothing written is the whole of the assertion, and the line that would
    /// otherwise appear is the alarm rather than anything milder: the tap is
    /// gone by this point, so the putting-back fails and the wording that
    /// follows is the one reserved for a tap that will not come back. The
    /// fake answers that the way the real one does, which is what lets this
    /// case stand for the real shutdown rather than for a friendlier
    /// rehearsal of it.
    @Test func aCheckArrivingAfterAStopWritesNothing() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.start()

        fixture.monitor.stop()
        fixture.monitor.checkHealth()

        #expect(fixture.log.lines.isEmpty)
        #expect(fixture.tap.enableCount == 0)
    }

    /// The asking is closed by a shutdown and not by the stop a developer asks
    /// for, which are opposite cases that would be easy to conflate in one
    /// flag. A deliberate stop is exactly what the asking exists to find and
    /// undo, so the check after it must still do its work.
    @Test func aStopAskedForLeavesTheAskingOpen() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.start()

        fixture.monitor.stopOnPurpose()
        fixture.monitor.checkHealth()

        #expect(fixture.tap.enableCount == 1)
        #expect(fixture.tap.isEnabled)
    }

    /// Long enough that a loop on the same interval would have come round, and
    /// no longer.
    ///
    /// The two cases above assert that nothing happened, and nothing happening
    /// is what a wait that ended too early looks like as well. So the wait is
    /// measured against a monitor that does have a loop, on the same interval,
    /// started at the same moment: once that one has asked, a turn has gone by
    /// on the actor both of them share. A fixed sleep could only guess at that,
    /// and would guess wrong on a machine busy enough — which is exactly the
    /// machine these cases run on, since the whole suite competes for this one
    /// actor.
    ///
    /// The time limits belong to the two callers rather than here, because a
    /// trait on a helper binds nothing: what has to be bounded is the test
    /// that ends up waiting, and the yardstick can only be as reliable as the
    /// loop it is measuring — if that stops being made, this waits for ever.
    private static func waitOutATurn() async {
        let yardstick = MonitorFixture(healthCheckInterval: .milliseconds(1))
        _ = yardstick.monitor.start()
        yardstick.tap.isEnabled = false
        await yardstick.tap.waitUntilAsked(times: 1)
        yardstick.monitor.stop()
    }

    /// The figure is spelled out by the caller rather than formatted here. A
    /// helper that ran the number through the same call the line does would
    /// agree with any formatting it was given, including the locale-sensitive
    /// kind the case above exists to rule out.
    private static func foundDisabled(_ figure: String) -> String {
        "modifier monitor was found disabled; re-enabled \(figure) ms after it went down"
    }
}
