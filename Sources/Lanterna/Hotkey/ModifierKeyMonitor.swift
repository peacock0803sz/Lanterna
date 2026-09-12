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
    /// How often the tap is asked whether it is still on. Unused until the
    /// recovery lands; kept in the initialiser now so the loop it paces has
    /// somewhere to read it from and tests have somewhere to shorten it.
    private let healthCheckInterval: Duration
    private let onCommandRelease: @MainActor () -> Void
    private let writeLine: @MainActor (String) -> Void

    /// What the first `start()` achieved. Present from that call onwards, and
    /// the reason a repeat call need attempt nothing.
    private var startOutcome: StartOutcome?

    init(
        tap: any EventTapControlling = SystemEventTap(),
        healthCheckInterval: Duration = .seconds(2),
        onCommandRelease: @escaping @MainActor () -> Void,
        writeLine: @escaping @MainActor (String) -> Void = Diagnostics.writeLine
    ) {
        self.tap = tap
        self.healthCheckInterval = healthCheckInterval
        self.onCommandRelease = onCommandRelease
        self.writeLine = writeLine
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
            // Notices are taken and dropped until the recovery lands. The
            // periodic check is the path that has to work on its own, since
            // whether a listen-only tap is ever sent one of these is folklore
            // rather than documented; this end of it is the optimisation.
            onDisabledBySystem: {}
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
    func stop() {
        tap.invalidate()
    }
}
