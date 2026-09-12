/// Owns the modifier tap: starts it once, says what that achieved, and takes
/// it down on the way out.
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

        /// Whether Command's release is going to be what closes the panel.
        /// The presenter's only question.
        var closesOnCommandRelease: Bool {
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

    private let tap: any EventTapControlling
    private let onCommandRelease: @MainActor () -> Void
    private let writeLine: @MainActor (String) -> Void

    /// What the first `start()` achieved. Present from that call onwards, and
    /// the reason a repeat call need attempt nothing.
    private var startOutcome: StartOutcome?

    init(
        tap: any EventTapControlling = SystemEventTap(),
        onCommandRelease: @escaping @MainActor () -> Void,
        writeLine: @escaping @MainActor (String) -> Void = Diagnostics.writeLine
    ) {
        self.tap = tap
        self.onCommandRelease = onCommandRelease
        self.writeLine = writeLine
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
        let outcome: StartOutcome = tap.start(
            onCommandRelease: onCommandRelease,
            // The notice is reported but not recovered from. Whether a
            // listen-only tap is ever sent one of these is folklore rather
            // than documented, so writing it down is the cheap half; what
            // would make recovery reliable is a check that does not depend on
            // being told.
            //
            // `writeLine` is captured rather than `self`: the tap holds this
            // closure and this object holds the tap, so naming `self` here
            // would close that loop and neither end would ever be released.
            onDisabledBySystem: { [writeLine] in
                writeLine(
                    "the system switched the modifier monitor off; the panel now closes on a "
                        + "second Cmd+Tab instead of when Command is released"
                )
            }
        )
            ? .started
            : .refused(hadPermission: tap.hasPermission)
        startOutcome = outcome
        return outcome
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
    func stop() {
        tap.invalidate()
    }
}
