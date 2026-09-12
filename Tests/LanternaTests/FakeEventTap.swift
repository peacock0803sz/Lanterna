@testable import Lanterna

/// Stands in for the system tap. A real one needs a login session and a
/// permission grant, and there is no way to ask it to fail on demand.
///
/// The point of the double is that the two kinds of stop can be told apart.
/// A stop the system announces is made by calling the held
/// `onDisabledBySystem`; a stop nothing announces is made by setting
/// `isEnabled` to false and saying nothing, which is the only kind the
/// periodic check can find. Anything that recovers from one but not the other
/// passes only one of them.
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
        guard enableSucceeds else { return false }
        isEnabled = true
        return true
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
