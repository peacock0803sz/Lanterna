@testable import Lanterna

/// Stands in for the monitor over this process's key presses, so a test can
/// hand one over without a keyboard.
///
/// In a file of its own rather than with the other doubles. The shared file
/// is within seventy-odd lines of the length the linter allows and the panel's
/// stand-in has just grown inside it; a double that needs nothing from the
/// others has no reason to be charged to that budget. The tap's and the
/// application's stand-ins are kept this way for the same reason.
///
/// What goes in is a press and not a meaning: a key, what was held with it,
/// and whether the keyboard was repeating. Injecting an already-decided
/// action instead would put the whole business of turning keys into meanings
/// outside anything a test drives, which is the one part of this layer that
/// can be checked exactly.
@MainActor
final class FakeKeyChannel: PanelKeyChannel {
    private var handler: (@MainActor (PanelKeystroke) -> PanelKeyDisposition)?

    private(set) var startCount = 0

    /// How many times the listening has been taken off, by either route.
    ///
    /// Every start adds one of these as well as one to the count above,
    /// because the real channel takes whatever was listening off before it
    /// installs anything. So two starts and no `stop()` leave this reading
    /// two, and a run of starts leaves the two counts equal rather than one
    /// standing at zero. Counting only the calls made from outside would have
    /// been the easier number to read and the wrong one: it would say the
    /// stand-in replaces without removing, which is the very thing the real
    /// channel refuses to do.
    private(set) var stopCount = 0

    /// Whether presses would be delivered at this instant.
    var isDelivering: Bool {
        handler != nil
    }

    /// Stops first, because `PanelKeyChannel` asks that of every implementation
    /// and this is one of them. A double is held to the contract rather than
    /// excused from it: one that merely swapped its handler over would let a
    /// test pass where the thing it stands in for would fail.
    ///
    /// Always answers yes. AppKit is the only party that can decline to hand a
    /// monitor over, and there is none here to decline; the refusal is staged
    /// against the real channel instead, where the answer is read back from
    /// what AppKit gave.
    func start(handler: @escaping @MainActor (PanelKeystroke) -> PanelKeyDisposition) -> Bool {
        stop()
        startCount += 1
        self.handler = handler
        return true
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    /// Delivers a press and answers as the real monitor would.
    ///
    /// Nothing at all when no one is listening, which is a different answer
    /// from either disposition: a monitor that was never started does not
    /// swallow a key, it never sees one.
    @discardableResult
    func send(_ keystroke: PanelKeystroke) -> PanelKeyDisposition? {
        handler?(keystroke)
    }
}
