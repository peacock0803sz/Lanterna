@testable import Lanterna

/// Stands in for the system tap. A real one needs a login session and a
/// permission grant, and there is no way to ask it to fail on demand.
///
/// The double can stage two kinds of stop, and only one of them is driven
/// today. A stop the system announces is made by calling the held
/// `onDisabledBySystem`, and a test does that: what it pins is that the notice
/// is written down, since nothing recovers from it. A stop nothing announces
/// is made by setting `isEnabled` to false through `disable()` — built, but no
/// test stages it, because only something polling `isEnabled` could tell that
/// it happened and nothing polls. `enable()` and `enableSucceeds` sit unused
/// for the same reason.
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
