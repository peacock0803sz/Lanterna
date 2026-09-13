/// Owns the modifier tap: starts it once, says what that achieved, keeps it
/// delivering for as long as the app runs, and takes it down on the way out.
///
/// Keeping it delivering takes two routes, because one of them cannot be
/// relied on alone. The system may announce that it has switched the tap off,
/// and that announcement is acted on the instant it lands; but whether a
/// listen-only tap is ever sent one is folklore rather than anything written
/// down. So the tap is also simply asked, on a loop, and every stop is caught
/// there — the announced ones and the silent ones alike. The loop is what
/// keeps a stop from outlasting `strandedPanelLimit`; being told merely makes
/// some of them quicker.
///
/// The tap arrives through the initialiser rather than being made here, so
/// every decision this class makes can be put to a test without a login
/// session or a permission grant.
@MainActor
final class ModifierKeyMonitor {
    /// What the one start attempt achieved.
    ///
    /// Attempted once and never revisited. A permission granted while the app
    /// is running does not change this run, for the same reason the window
    /// list settles its own permission at launch: a system dialog answering a
    /// key press is a worse thing to explain than a log line saying which way
    /// this run went.
    enum StartOutcome: Sendable, Equatable {
        case started
        /// The system would not create a tap. `hadPermission` is what the
        /// preflight said, which is the difference between "grant it" and
        /// "something else is wrong".
        case refused(hadPermission: Bool)

        /// Whether the attempt left a tap behind.
        ///
        /// Asked by whatever only makes sense with one — the deliberate stops
        /// in `AppDelegate.stopPeriodically`, which have nothing to stop
        /// otherwise. Named for that question rather than for the panel's,
        /// because the two only look alike while there are two cases: this is
        /// about what the one attempt achieved, and it cannot go stale.
        ///
        /// Not the question the presenter asks. Whether a release is going to
        /// close the panel can stop being true under the app at any moment, so
        /// that one is put to the tap itself through
        /// `ModifierKeyMonitor.isMonitoring` rather than to an outcome settled
        /// once at launch.
        var producedATap: Bool {
            self == .started
        }

        /// The one line written after the attempt, which is also the first of
        /// the two pieces of evidence that a run fell back: the second is
        /// that `panel hidden (Cmd+Tab)` shows up at all.
        var summaryLine: String {
            switch self {
            case .started:
                "modifier monitor started; the panel closes when Command is released"
            case .refused(hadPermission: false):
                "modifier monitor could not start; input monitoring is not granted, so the "
                    + "panel closes on a second Cmd+Tab instead; grant it in System Settings "
                    + "> Privacy & Security > Input Monitoring and restart the app"
            case .refused(hadPermission: true):
                "modifier monitor could not start even though input monitoring is granted; "
                    + "the panel closes on a second Cmd+Tab instead"
            }
        }
    }

    /// How long a panel may be left up with nothing able to close it.
    ///
    /// Named so the figure lives in the code it governs rather than in prose
    /// only some readers will have met. Nothing imposes it and nothing
    /// enforces it at run time: a panel outliving its gesture by a moment
    /// reads as slow and by ten seconds as broken, five is where this app
    /// draws that line, and it is the budget the numbers below are picked to
    /// fit.
    static let strandedPanelLimit: Duration = .seconds(5)

    /// How long the loop waits between asking the tap whether it is still
    /// delivering.
    ///
    /// Shorter than `strandedPanelLimit`, with room to spare: at an interval
    /// of five the worst case would land over that limit rather than under it.
    /// Asking is cheap — one `tapIsEnabled` against a whole pass over every
    /// application's windows — so the extra wake-ups do not show up in an idle
    /// process's share of the processor. They are its own wake-ups, though:
    /// two seconds and the 1.5 the list waits between passes coincide only
    /// every six, so three checks in four wake the machine on their own
    /// account. Cheap rather than free.
    ///
    /// A loop of its own rather than a ride on the list's. A pass over the
    /// windows stretches towards two seconds whenever one application has
    /// stopped answering, and sharing the timer would turn that stretch into a
    /// late check — making how long a stranded panel lasts depend on how
    /// quickly other applications reply.
    static let defaultHealthCheckInterval: Duration = .seconds(2)

    private let tap: any EventTapControlling
    private let healthCheckInterval: Duration
    private let onCommandRelease: @MainActor () -> Void
    private let now: @MainActor () -> ContinuousClock.Instant
    private let writeLine: @MainActor (String) -> Void

    /// What the first `start()` achieved. Present from that call onwards, and
    /// the reason a repeat call need attempt nothing.
    private var startOutcome: StartOutcome?

    /// The loop that asks. Exists only after a `start()` that produced a tap.
    private var healthCheckTask: Task<Void, Never>?

    /// Whether the run has been taken down, which is the one state in which a
    /// check is refused rather than answered.
    ///
    /// Kept rather than left to the loop's own cancellation, because the loop
    /// is not the only way in: `checkHealth()` is reachable by anyone holding
    /// the monitor, and a cancelled turn and a call made by hand arrive at the
    /// writing by different roads. The refusal belongs where the line would be
    /// written, so that neither road can reach it.
    ///
    /// `stopOnPurpose()` deliberately leaves this alone. That stop is one the
    /// asking is meant to find and undo, and an asking that gave up on it
    /// would defeat the only thing it is for.
    private var hasStopped = false

    /// When the tap was last seen delivering, which is where the figure in the
    /// re-enabled line is measured from.
    ///
    /// Moved at three points and nowhere else: a successful `start()`, a check
    /// that finds the tap still enabled, and every successful `enable()`
    /// whichever route asked for it. Pinning it to those three is what makes
    /// the figure mean the same thing from one run to the next — left to taste
    /// it could as easily be measured from the launch, from the previous
    /// wake-up, or from the last time the tap came back, and three readings of
    /// three different spans cannot be compared with each other.
    ///
    /// Seeded here rather than left absent until the first of those, so that
    /// there is always a span to measure and never a figure standing for the
    /// absence of one. Nothing reads the seeded value: the only route to the
    /// figure runs through the loop, which exists solely after a `start()`
    /// that has already moved it. An optional would have bought a case that
    /// cannot arise, at the price of a fallback reading zero — and zero
    /// under-states, which is the wrong direction to be wrong in.
    ///
    /// The moment the tap actually went down is not knowable, so this is an
    /// over-estimate of how long it was out. That is the safe way to be wrong
    /// about a figure judged against an upper limit.
    private var lastKnownEnabledAt: ContinuousClock.Instant

    init(
        tap: any EventTapControlling = SystemEventTap(),
        healthCheckInterval: Duration = defaultHealthCheckInterval,
        onCommandRelease: @escaping @MainActor () -> Void,
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        writeLine: @escaping @MainActor (String) -> Void = Diagnostics.writeLine
    ) {
        self.tap = tap
        self.healthCheckInterval = healthCheckInterval
        self.onCommandRelease = onCommandRelease
        self.now = now
        self.writeLine = writeLine
        // Through the injected clock rather than from the system's, so that a
        // test's reading of time is the only one this object ever has.
        lastKnownEnabledAt = now()
    }

    /// Whether the tap is delivering events at this moment.
    ///
    /// Asked rather than remembered. What `start()` returned is about the one
    /// attempt it made and cannot go stale, but whether the tap is still
    /// delivering can change under the app at any moment — the system is free
    /// to switch a tap off long after it handed one over. Something deciding
    /// behaviour per keystroke has to ask, not recall.
    var isMonitoring: Bool {
        tap.isEnabled
    }

    /// Attempts the tap once and remembers the answer.
    ///
    /// The answer is remembered for the same reason `HotkeyManager.register()`
    /// remembers its own: a second attempt would leave two taps on the run
    /// loop, both live, and every release would then be reported twice.
    ///
    /// Whether the tap could be made is the whole of the decision. The
    /// preflight is read only after a refusal, and only to word the line:
    /// there are reports that Accessibility alone is enough to create a tap,
    /// which is not written down anywhere official, and hanging the decision
    /// on the return value rather than on the preflight is what makes it not
    /// matter which of them is true.
    func start() -> StartOutcome {
        if let startOutcome {
            return startOutcome
        }
        let started = tap.start(
            onCommandRelease: onCommandRelease,
            // Weakly held. The tap keeps this closure and this object keeps
            // the tap, so a strong `self` here would close that ring and
            // neither end would ever be let go.
            onDisabledBySystem: { [weak self] in self?.putBackAfterBeingTold() }
        )
        let outcome: StartOutcome = started
            ? .started
            : .refused(hadPermission: tap.hasPermission)
        startOutcome = outcome
        if started {
            lastKnownEnabledAt = now()
            startHealthChecks()
        }
        return outcome
    }

    /// Asks the tap whether it is still delivering, and puts it back if it is
    /// not.
    ///
    /// The route that does not depend on being told, and on its own enough to
    /// keep a panel from being stranded: every stop passes through here, the
    /// ones that announce themselves and the ones that do not. Being told is
    /// only what makes some of them quicker.
    ///
    /// Called by the loop, and directly by tests, which is why it is not
    /// private — waiting out real seconds to reach it would put the length of
    /// the interval into the time the suite takes.
    ///
    /// A tap found still enabled is passed over in silence. A line every two
    /// seconds saying nothing had happened would, alongside the list's own
    /// pass, leave a log in which the things that did happen could not be
    /// found.
    func checkHealth() {
        // Refused after a shutdown rather than answered, for the reason
        // `stop()` sets out: the tap is gone by then, so the only thing this
        // could write is an alarm about a panel nothing can close.
        guard !hasStopped else { return }
        let checkedAt = now()
        guard !tap.isEnabled else {
            lastKnownEnabledAt = checkedAt
            return
        }
        // Read before the putting-back moves it.
        let downFor = checkedAt - lastKnownEnabledAt
        guard enableTap() else {
            writeLine("modifier monitor was found disabled; could not re-enable it")
            return
        }
        writeLine(
            "modifier monitor was found disabled; re-enabled "
                + "\(Diagnostics.millisecondsText(downFor)) ms after it went down"
        )
    }

    /// The route that depends on being told: the system says it has switched
    /// the tap off, and it goes straight back on.
    ///
    /// No figure. Being told is the moment it happened, so there is no span
    /// between the two to measure.
    private func putBackAfterBeingTold() {
        guard enableTap() else {
            writeLine("modifier monitor was disabled by the system; could not re-enable it")
            return
        }
        writeLine("modifier monitor was disabled by the system; re-enabled")
    }

    /// `enable()` and the one thing every successful enabling owes: moving the
    /// instant the figure above is measured from. Both routes come through
    /// here so neither can forget.
    private func enableTap() -> Bool {
        guard tap.enable() else { return false }
        lastKnownEnabledAt = now()
        return true
    }

    /// Starts the asking. Reached only from a `start()` that produced a tap.
    ///
    /// A refused run gets no loop. There would be nothing for it to ask about,
    /// and the wake-up every couple of seconds would be charged to an idle
    /// process for the rest of its life.
    ///
    /// Sleeps before the first ask rather than after. The tap was enabled a
    /// moment ago by the call that led here, so an immediate check could only
    /// confirm what was just read.
    private func startHealthChecks() {
        // `weak` because this object holds the task: a strong capture would be
        // the monitor kept alive by its own loop. The interval is taken by
        // value alongside it, so the wait between asks does not itself depend
        // on the monitor still being there.
        healthCheckTask = Task { [weak self, healthCheckInterval] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: healthCheckInterval)
                } catch {
                    // Cancellation is the only way the sleep fails, and it is
                    // how the loop is meant to end.
                    return
                }
                // Asked again after the wait, because a cancellation landing
                // while this turn was already queued on the actor does not
                // call it back: the sleep had finished, so it threw nothing,
                // and without this the turn would run against a tap that the
                // same shutdown had just taken down.
                guard !Task.isCancelled else { return }
                // Ends rather than idles on when the owner has gone. Left as
                // an optional call the loop would wake every two seconds to do
                // nothing, for as long as the process lived.
                guard let self else { return }
                checkHealth()
            }
        }
    }

    /// The line announcing that the deliberate stops are switched on, written
    /// once at launch by whatever arranges them.
    ///
    /// Made here rather than where it is written, so the wording is somewhere
    /// a test can reach: the one place it is written from is a private method
    /// of `AppDelegate`, inside a launch that cannot be got at to read a
    /// string back. Whole seconds, because the flag takes whole seconds, and
    /// read off the `Duration` rather than put through a formatter, so the
    /// figure reads the same whatever the machine is set to.
    static func periodicStopAnnouncement(every period: Duration) -> String {
        "stopping the modifier monitor every \(period.components.seconds) s "
            + "(\(LaunchArguments.stopMonitorEveryFlag.name))"
    }

    /// Switches the tap off deliberately, so the loop can be watched putting
    /// it back.
    ///
    /// Silent by nature, and that is the whole reason it is useful: a stop
    /// asked for here is taken to send no notice, not even to the process that
    /// asked, so the quick route cannot see it and the asking is the only
    /// thing that can. It therefore stages the one kind of stop that staying
    /// inside `strandedPanelLimit` actually depends on, rather than the kind
    /// that announces itself.
    ///
    /// That silence is an assumption, and nothing here establishes it: the
    /// case that appears to check it runs against `FakeEventTap`, written not
    /// to call the notice back, so it agrees with the belief it was built
    /// from. The design does rest on it — were a self-requested disable to
    /// announce itself after all, this would stage the told route while
    /// appearing to stage the other.
    ///
    /// The tap is reached through this rather than handed out, because the tap
    /// is this object's and a caller that could switch it off could as easily
    /// switch it off without anything saying so.
    ///
    /// Says which way it went rather than announcing a stop either way, and
    /// the silence this feature is built on is exactly why. A disable that did
    /// not take leaves the tap delivering; the check that follows then finds
    /// nothing wrong and passes over without a word, by design. What is left
    /// on the page is a stop announced every period and never a recovery
    /// answering it — character for character what a recovery that had
    /// stopped working writes. A developer reading that would go looking at
    /// the recovery, which is the one place the fault would not be.
    func stopOnPurpose() {
        guard tap.disable() else {
            writeLine(
                "modifier monitor could not be stopped on purpose "
                    + "(\(LaunchArguments.stopMonitorEveryFlag.name))"
            )
            return
        }
        writeLine(
            "modifier monitor stopped on purpose "
                + "(\(LaunchArguments.stopMonitorEveryFlag.name))"
        )
    }

    /// Takes the tap down.
    ///
    /// Called from the shutdown path after the system's own shortcuts have
    /// been put back, never before: the tap goes away with the process
    /// whatever happens here, while a shortcut left switched off outlives it.
    ///
    /// The outcome is kept rather than forgotten, which is where this parts
    /// company with `HotkeyManager.unregister()`. That one forgets so a later
    /// call can claim the combinations again; this has nothing to claim again.
    /// What it is holding is the answer to a question asked once a launch —
    /// whether this run has a monitor — and a `stop()` on the way out is not
    /// the run changing its mind.
    ///
    /// The tap goes first and the loop second, which leaves a check already
    /// past its sleep still to come: cancelling a task raises a flag, and does
    /// not call back a turn the actor has already been handed. Such a turn is
    /// refused rather than run — the loop asks again when it wakes, and the
    /// asking is closed here for anyone else holding the monitor — because a
    /// check made after this would find the tap gone, fail to put one back,
    /// and write the line that says a panel is stuck with nothing able to
    /// close it. A shutdown that left that behind could not be told apart from
    /// the trouble it names.
    ///
    /// Every operation on `EventTapControlling` is defined to be safe with no
    /// tap in hand regardless, and that is still worth having. But it is about
    /// not crashing rather than about what gets written, which is why it was
    /// never on its own an answer to this.
    func stop() {
        hasStopped = true
        tap.invalidate()
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }
}
