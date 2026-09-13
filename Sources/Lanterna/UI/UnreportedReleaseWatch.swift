/// Looks for Command having been let go when nothing said so.
///
/// The panel closes on the tap reporting Command going up. A tap that is
/// enabled but is not being handed events reports nothing, and then nothing
/// closes the panel at all: it is non-activating and takes no keys of its own,
/// and a further press is turned away for as long as a monitor is running. So
/// the keyboard is asked directly instead, on a short interval, for as long as
/// the panel is up.
///
/// Asking does not travel the tap's delivery path, and that independence is
/// the whole point. The answer comes from the session's own record of the
/// keyboard — `CGEventSource.flagsState(.combinedSessionState)`, in the run
/// that matters — rather than from anything handed to a tap. Secure event
/// input holds keyboard events back from session taps without disabling them,
/// and a tap ahead of this app's in the chain can consume the event before it
/// arrives; neither of those shows as a monitor that has stopped, and nothing
/// here has to work out which it was.
///
/// Every way the delivery can go is covered by that. Where the tap delivers,
/// the reported release takes the panel down first and the look finds nothing
/// up. Where it is starved, the look finds the release nobody reported. Where
/// the modifier state cannot be read either, it answers no at press time and
/// the press is turned away before there is a panel to look after.
///
/// This only notices. What a noticing is worth saying about, and what taking
/// the panel down means, belong to whoever holds one of these — the noticing
/// is the same either way, and it is the only part that has to be right about
/// the system.
@MainActor
final class UnreportedReleaseWatch {
    /// How long to wait between looks, and so about how long a panel can
    /// outlive a release nothing reported.
    ///
    /// About, and not at most: the sleep below may be granted tolerance and
    /// come back later than it was asked to, which is a thing worth wanting
    /// from a timer that fires while nothing else is happening. It costs
    /// nothing here, because every look reads the state afresh rather than
    /// inferring anything from how long it slept.
    ///
    /// A tap that is being handed events has its callback on the main run loop
    /// within microseconds of the event, so a twentieth of a second leaves the
    /// reported release three orders of magnitude in which to get there first.
    /// This is meant to find the releases that never arrive, not to race the
    /// ones that do. It is short enough at the other end too: a panel closed a
    /// twentieth of a second late reads as closed rather than as stuck. Ten
    /// times shorter would ask the window server twenty times a second for an
    /// answer that is the same almost every time.
    static let defaultInterval: Duration = .milliseconds(50)

    private let interval: Duration

    /// Whether the panel is still up, asked afresh after every wait. The panel
    /// can go down while this is asleep, and a look acting on one that had
    /// already gone would be acting on nothing.
    private let isPanelUp: @MainActor () -> Bool

    /// Whether Command is down on the keyboard at this instant.
    ///
    /// Passed in rather than read here, so that what this asks and what the
    /// press-time check asks are one question with one answer, and so that a
    /// test process — which cannot hold a real Command key down — can put it
    /// either way.
    private let commandIsHeld: @MainActor () -> Bool

    /// Run once, on finding a release that nothing reported.
    private let onUnreportedRelease: @MainActor () -> Void

    private var task: Task<Void, Never>?

    /// Whether a look is under way, which is to say whether the panel now on
    /// screen has anything watching over it.
    ///
    /// The presenter asks because the two can come apart. A panel put up while
    /// no monitor was running is given no watch — there was no reported
    /// release for one to stand in for — and a monitor that comes back while
    /// that panel is still up does not go back and start one: it takes its
    /// idea of the modifiers from the keyboard as it finds it, so a Command
    /// let go in the meantime leaves no release for it to report. A press is
    /// that panel's only way off the screen, and a monitor answering yes after
    /// the fact must not be enough on its own to take that press away.
    var isLooking: Bool {
        task != nil
    }

    init(
        interval: Duration = defaultInterval,
        isPanelUp: @escaping @MainActor () -> Bool,
        commandIsHeld: @escaping @MainActor () -> Bool,
        onUnreportedRelease: @escaping @MainActor () -> Void
    ) {
        self.interval = interval
        self.isPanelUp = isPanelUp
        self.commandIsHeld = commandIsHeld
        self.onUnreportedRelease = onUnreportedRelease
    }

    /// Looks until the release is found, the panel goes, or `stop()`.
    ///
    /// Stops whatever it started before, the way the window list's loop does:
    /// two loops watching one panel would find one release twice, and the
    /// second would report a panel that the first had already taken down.
    ///
    /// The first look is a whole interval away rather than immediate. A press
    /// arriving with Command already up is turned away before any panel
    /// appears, so a panel that has just gone up is a panel whose Command was
    /// down a moment ago, and there is nothing for an immediate look to find.
    func start() {
        stop()
        // Read out here because the interval is wanted before there is a
        // `self` to read it from: the first thing the loop does is wait.
        let betweenLooks = interval
        // `weak` because the task is held here, so a strong capture would be
        // this object kept alive by its own loop. The other side of that is
        // worth knowing: a watch nobody holds stops looking at its next wait.
        // Whoever wants the looking done has to keep hold of it — the
        // presenter does, for as long as it lives, and a test driving one of
        // these directly has to as well, or it will read the silence of a
        // collected watch as a watch that correctly found nothing.
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: betweenLooks)
                } catch {
                    // Cancellation is the only way the sleep fails, and it is
                    // one of the ways this is meant to end.
                    return
                }
                guard let self, isPanelUp() else { return }
                // Still held is the ordinary case — someone holding Command
                // and tapping along the list — and it is why this waits round
                // again rather than giving up.
                guard !commandIsHeld() else { continue }
                onUnreportedRelease()
                return
            }
        }
    }

    /// Ends the looking. A look that never happened reports nothing.
    ///
    /// Safe to call from inside the reporting itself, which is in fact the
    /// ordinary way round: the callback takes the panel down, and taking the
    /// panel down is what stops the watch. The task cancelling itself costs
    /// nothing here, because the loop returns on the line after the callback
    /// rather than going back to sleep — cancellation only ever matters to a
    /// wait still to come.
    func stop() {
        task?.cancel()
        task = nil
    }
}
