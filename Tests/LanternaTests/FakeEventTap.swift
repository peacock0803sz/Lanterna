@testable import Lanterna

/// Stands in for the system tap. A real one needs a login session and a
/// permission grant, and there is no way to ask it to fail on demand.
///
/// The double stages both kinds of stop, which is the whole of what it is for.
/// A stop the system announces is made by calling the held
/// `onDisabledBySystem`; a stop nothing announces is made by putting
/// `isEnabled` down, either directly or through `disable()`, and can be found
/// only by something that asks. `enableSucceeds` holds a tap that will not
/// come back, which is the one state a panel can be stranded in and is
/// reachable no other way.
@MainActor
final class FakeEventTap: EventTapControlling {
    var hasPermission = true
    var isEnabled = false

    /// What `start` will answer. False is a system that would not hand a tap
    /// over, which is the one thing the fallback is decided on.
    var startSucceeds = true
    /// What `enable` will answer, so a tap that cannot be brought back can be
    /// held that way.
    var enableSucceeds = true

    private(set) var startCount = 0
    private(set) var enableCount = 0
    private(set) var disableCount = 0
    private(set) var invalidateCount = 0

    private var onCommandRelease: (@MainActor () -> Void)?
    private var onDisabledBySystem: (@MainActor () -> Void)?
    private var asked: CheckedContinuation<Void, Never>?
    private var awaitedCount = 0

    func start(
        onCommandRelease: @escaping @MainActor () -> Void,
        onDisabledBySystem: @escaping @MainActor () -> Void
    ) -> Bool {
        startCount += 1
        guard startSucceeds else { return false }
        self.onCommandRelease = onCommandRelease
        self.onDisabledBySystem = onDisabledBySystem
        isEnabled = true
        return true
    }

    func enable() -> Bool {
        enableCount += 1
        if enableCount >= awaitedCount {
            asked?.resume()
            asked = nil
        }
        guard enableSucceeds else { return false }
        isEnabled = true
        return true
    }

    /// Parks until the tap has been asked for back `times` times over.
    ///
    /// For the cases that drive the monitor's loop rather than calling its
    /// check by hand. A fixed sleep would have to guess how long a turn takes,
    /// and the guess is wrong in both directions: too short and a suite busy
    /// enough to keep every other test on the main actor makes it fail, too
    /// long and every run pays for the worst machine it might meet.
    ///
    /// Counted rather than waited for once, the way `CountingGather` counts
    /// the store's passes. One ask says a timer fired; only a run of them says
    /// there is a loop behind it, and a monitor whose asking stopped after the
    /// first turn is exactly the failure that would otherwise go unnoticed.
    /// The count waited on is the one the test reads afterwards, so what was
    /// waited for and what is asserted cannot come apart.
    ///
    /// One waiter at a time, said loudly rather than quietly. A second would
    /// overwrite the first's continuation, and the first would then never be
    /// resumed: the runtime calls that a leaked continuation and names the
    /// continuation, not the test that stranded it, which leaves whoever meets
    /// it looking for the wrong thing. A queue would make two waiters legal,
    /// but nothing here wants two, so this traps instead — the cheaper of the
    /// two ways to make sure the mistake cannot be made in silence.
    ///
    /// Gives the wait up when the task is cancelled, which is what lets a time
    /// limit on the caller mean anything. A plain `withCheckedContinuation`
    /// cannot be cancelled: the trait duly cancels the test, the wait carries
    /// on regardless, and a run whose loop stopped being made hangs for as
    /// long as anyone lets it rather than going red. Giving up returns to the
    /// caller with the count short, so the assertion after the wait is what
    /// reports the failure — a test that hangs says nothing about why.
    func waitUntilAsked(times: Int) async {
        guard enableCount < times else { return }
        precondition(asked == nil, "FakeEventTap supports one waiter at a time")
        awaitedCount = times
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Cancellation can arrive before there is anything to resume.
                // Both orders end the wait, because whichever of the two runs
                // second finds what the first left: this sees the flag, or
                // the handler below sees the continuation.
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    asked = continuation
                }
            }
        } onCancel: {
            // Hops back because cancellation is delivered wherever it happens
            // and everything here belongs to the main actor. The actor being
            // serial is what makes the pair of them safe: one resume runs to
            // completion before the other can look.
            Task { @MainActor in
                asked?.resume()
                asked = nil
            }
        }
    }

    func disable() {
        disableCount += 1
        isEnabled = false
    }

    func invalidate() {
        invalidateCount += 1
        isEnabled = false
        onCommandRelease = nil
        onDisabledBySystem = nil
    }

    /// Command being let go, as the real tap would report it. Does nothing
    /// before a successful `start` and after `invalidate`, which is the
    /// truthful answer in both cases.
    func reportCommandRelease() {
        onCommandRelease?()
    }

    /// The system announcing that it has switched the tap off. Leaves
    /// `isEnabled` alone so a test can decide whether the notice arrives with
    /// the tap genuinely down or, as a wedged one would, without.
    func reportDisabledBySystem() {
        onDisabledBySystem?()
    }
}
