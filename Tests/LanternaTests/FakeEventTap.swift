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
        asked?.resume()
        asked = nil
        guard enableSucceeds else { return false }
        isEnabled = true
        return true
    }

    /// Parks until something has asked for the tap back.
    ///
    /// For the cases that drive the monitor's loop rather than calling its
    /// check by hand. A fixed sleep would have to guess how long a turn takes,
    /// and the guess is wrong in both directions: too short and a suite busy
    /// enough to keep every other test on the main actor makes it fail, too
    /// long and every run pays for the worst machine it might meet.
    func waitUntilAsked() async {
        guard enableCount == 0 else { return }
        await withCheckedContinuation { asked = $0 }
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
