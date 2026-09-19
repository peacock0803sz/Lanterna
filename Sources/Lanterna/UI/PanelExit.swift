/// Every way the panel comes off the screen, and the line each of them
/// writes.
///
/// Split from the presenter, which decides when a panel goes up. When one
/// comes down is a different question, and it is the one with state of its
/// own: the row being shown exists only while the panel does, and every way
/// out reads it or clears it. The ways out are called from the presenter and
/// so are visible to the module; keeping the row here, beside them, is what
/// lets the row itself and the one step that takes the panel down stay
/// private to this file — an extension elsewhere could only reach those two
/// by making them visible to the whole module.
///
/// The weaker of the two invariants this used to hold is the one that still
/// holds: every time the panel goes, exactly one line says why. Saying it
/// twice would be no better than not at all — counting the lines afterwards
/// would find two events where the user saw one.
@MainActor
final class PanelExit {
    private let surface: any SwitcherSurface
    private let now: @MainActor () -> ContinuousClock.Instant
    private let writeLine: @MainActor (String) -> Void

    /// Run whenever the panel goes, whichever way it went.
    ///
    /// A closure rather than the watch itself, because what is being stopped
    /// is the holder's business: this knows only that the looking covers the
    /// panel's time on screen exactly, and that the panel's time is over.
    private let stopWatching: @MainActor () -> Void

    /// The row the panel is showing as selected, kept so a commit can name
    /// it.
    ///
    /// `displayTitle` and not `windowTitle`: the latter may be empty or hold
    /// nothing but whitespace, and the panel shows the application's name in
    /// that case. A line disagreeing with the panel would be worse than no
    /// line. The selection does not move yet, so this is the first row of
    /// whatever was presented.
    private var selectedWindow: (appName: String, displayTitle: String)?

    init(
        surface: any SwitcherSurface,
        now: @escaping @MainActor () -> ContinuousClock.Instant,
        writeLine: @escaping @MainActor (String) -> Void,
        stopWatching: @escaping @MainActor () -> Void
    ) {
        self.surface = surface
        self.now = now
        self.writeLine = writeLine
        self.stopWatching = stopWatching
    }

    /// Takes down which row an appearance is showing.
    ///
    /// Read as the panel goes up rather than off the panel at commit time, so
    /// what a commit names is the list that appearance was given.
    func nowShowing(_ windows: [WindowItem]) {
        selectedWindow = windows.first.map {
            (appName: $0.appName, displayTitle: $0.displayTitle)
        }
    }

    /// Commits on Command having been let go over a panel that is up.
    ///
    /// With no panel the release is somebody finishing a Cmd+C, and nothing
    /// is said. A log with a line per keystroke is a log nobody reads.
    func commitOnCommandRelease(since startedAt: ContinuousClock.Instant) {
        guard surface.isPresented else { return }

        // Read before the panel goes, because taking it down is what clears
        // the selection.
        let outcome: CommandReleaseMeasurement.Outcome = selectedWindow.map {
            .committed(appName: $0.appName, displayTitle: $0.displayTitle)
        } ?? .nothingToCommit
        dismissPanel()
        record(outcome, since: startedAt)
    }

    /// Writes down a press given up on before it ever became a panel.
    ///
    /// Kept apart from a commit over an empty list because the two have
    /// different causes and different answers: one means the list was
    /// gathered and held nothing, the other that there was no list yet.
    func recordPressCalledOff(since startedAt: ContinuousClock.Instant) {
        record(.pressCalledOff, since: startedAt)
    }

    /// Takes the panel down for a release that came by no route at all.
    ///
    /// Plainly worded rather than measured, and deliberately not put through
    /// the commit above: every figure in those lines spans from Command being
    /// released to the panel being hidden, and this release was found by
    /// looking rather than reported, so it happened up to one interval before
    /// anything here knew of it and a figure begun at the noticing would read
    /// low. This project takes those figures for measurements, and one that
    /// quietly understates is worse than an event of its own.
    ///
    /// The row is read before the panel goes, for the reason a commit reads
    /// it there: taking the panel down is what clears the selection.
    /// Flattened by the same code a commit's is, so one row cannot be named
    /// two ways and a window titled across two lines cannot print this event
    /// as two.
    func closeForAnUnreportedRelease() {
        let row = selectedWindow.map {
            CommandReleaseMeasurement.rowDescription(appName: $0.appName, displayTitle: $0.displayTitle)
        }
        dismissPanel()
        writeLine(
            "closed the panel showing \(row ?? "nothing"); "
                + "Command was let go and the tap never said so"
        )
    }

    /// The wording for the disappearances that are the app tidying up after
    /// itself rather than the user deciding anything.
    func takeDown(because reason: String) {
        dismissPanel()
        writeLine("panel hidden (\(reason))")
    }

    /// The one place the panel comes off the screen.
    ///
    /// The selection goes with the panel. Nothing reads it while the panel is
    /// down, so no sequence of calls can tell whether this line is here — it
    /// is kept because a row outliving the panel it was on is the kind of
    /// thing that would already be wrong the moment the selection can move.
    private func dismissPanel() {
        surface.dismiss()
        selectedWindow = nil
        // Stopped here rather than at each way out, so the looking covers the
        // panel's time on screen exactly — the watch's own way out included.
        stopWatching()
    }

    /// Reads the clock after the work, so the figure spans exactly the part
    /// this process is answerable for.
    private func record(
        _ outcome: CommandReleaseMeasurement.Outcome,
        since startedAt: ContinuousClock.Instant
    ) {
        let measurement = CommandReleaseMeasurement(
            outcome: outcome,
            elapsed: now() - startedAt
        )
        writeLine(measurement.summaryLine)
    }
}
