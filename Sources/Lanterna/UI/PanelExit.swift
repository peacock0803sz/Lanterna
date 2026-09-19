/// Every way the panel comes off the screen, and the line each of them
/// writes.
///
/// Split from the presenter, which decides when a panel goes up. When one
/// comes down is a different question, and it is the one with state of its
/// own: the list being shown exists only while the panel does, and every way
/// out that names a row reads it or clears it. The ways out are called from
/// the presenter and so are visible to the module; keeping the list here,
/// beside them, is what lets the list itself and the one step that takes the
/// panel down stay private to this file — an extension elsewhere could only
/// reach those two by making them visible to the whole module.
///
/// Which row of that list is chosen is not kept here, and the line is drawn
/// where it is on purpose. Moving the choice is an answer to a keystroke, and
/// answering keystrokes is the presenter's. What is left here is the only way
/// back from the identity it hands over to the words that name it.
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
    /// A closure rather than the things it ends, because what those are is the
    /// holder's business: this knows only that they last exactly as long as
    /// the panel does, and that the panel's time is over. The looking for a
    /// release is one of them, the chosen row the other.
    private let onPanelGone: @MainActor () -> Void

    /// The list the panel is showing, kept so a line can name a row of it.
    ///
    /// The list and not a row read off it. Which row is chosen moves while
    /// the panel is up, so a row taken once would name whatever was chosen
    /// first however far the choice had travelled since.
    ///
    /// Taken as the panel goes up rather than asked of the window list at the
    /// time, so what a line names is the list that appearance was given. A
    /// fresher list could name a row this appearance never showed.
    private var presentedWindows: [WindowItem] = []

    init(
        surface: any SwitcherSurface,
        now: @escaping @MainActor () -> ContinuousClock.Instant,
        writeLine: @escaping @MainActor (String) -> Void,
        onPanelGone: @escaping @MainActor () -> Void
    ) {
        self.surface = surface
        self.now = now
        self.writeLine = writeLine
        self.onPanelGone = onPanelGone
    }

    /// Takes down the list an appearance is showing.
    func nowShowing(_ windows: [WindowItem]) {
        presentedWindows = windows
    }

    /// Commits on Command having been let go over a panel that is up.
    ///
    /// With no panel the release is somebody finishing a Cmd+C, and nothing
    /// is said. A log with a line per keystroke is a log nobody reads.
    ///
    /// The chosen row arrives as an identity rather than being read off
    /// anything here, because the only record of which row is chosen is the
    /// caller's. Looked up before the panel goes, because taking it down is
    /// what throws the list away.
    func commitOnCommandRelease(
        naming id: WindowItem.Identifier?,
        since startedAt: ContinuousClock.Instant
    ) {
        guard surface.isPresented else { return }

        let outcome: CommandReleaseMeasurement.Outcome = row(for: id).map {
            .committed(appName: $0.appName, displayTitle: $0.displayTitle, id: $0.id)
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
    /// The row is looked up before the panel goes, for the reason a commit
    /// looks it up there: taking the panel down is what throws the list away.
    /// Flattened by the same code a commit's is, so one row cannot be named
    /// two ways and a window titled across two lines cannot print this event
    /// as two.
    func closeForAnUnreportedRelease(naming id: WindowItem.Identifier?) {
        let named = row(for: id).map {
            CommandReleaseMeasurement.rowDescription(
                appName: $0.appName,
                displayTitle: $0.displayTitle,
                id: $0.id
            )
        }
        dismissPanel()
        writeLine(
            "closed the panel showing \(named ?? "nothing"); "
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
    /// The list goes with the panel. Nothing reads it while the panel is
    /// down, so no sequence of calls can tell whether this line is here — it
    /// is kept because a list outliving the panel it was drawn on could name
    /// a row for an appearance that never showed it.
    private func dismissPanel() {
        surface.dismiss()
        presentedWindows = []
        // Run here rather than at each way out, so whatever lasts the panel's
        // time on screen covers it exactly — the watch's own way out included.
        onPanelGone()
    }

    /// Names a row of the list on screen, or nothing when the identity names
    /// no row of it — which covers an empty list and a panel that is down.
    ///
    /// The one way in this process from an identity to the words for it. Two
    /// would be two derivations of one thing, and one row named two ways is
    /// what the log is not allowed to show.
    ///
    /// The whole row and not the three fields a line reads off it. Narrowing
    /// here would put the choice of which fields name a row in two places —
    /// here and in the wording — and the wording is where it belongs.
    private func row(for id: WindowItem.Identifier?) -> WindowItem? {
        guard let id else { return nil }
        return presentedWindows.first { $0.id == id }
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
