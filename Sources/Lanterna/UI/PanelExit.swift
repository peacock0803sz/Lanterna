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
/// where it is on purpose: naming a row is what an exit does, and choosing
/// one is not. The choice belongs to `PanelSelection`, which the two things
/// that move it — a keystroke and a further press of the combination — both
/// reach. What is left here is the only way back from the identity they hand
/// over to the words that name it.
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

    /// The looking that notices key presses no longer reaching the panel.
    ///
    /// Owned here rather than by the presenter, and the span is the reason:
    /// the looking lasts exactly as long as the panel is up, and going up
    /// and coming down both run through this type. What it reports back are
    /// also this type's own operations — a line, or taking the panel down —
    /// so nothing here reaches back out except through the one closure that
    /// ends the other things lasting the panel's time.
    ///
    /// `lazy` because every question it puts and both answers it gives back
    /// are this object's, and closures over `self` cannot be written until
    /// the stored properties are in place.
    private lazy var keyWatch = KeyStatusWatch(
        interval: keyStatusWatchInterval,
        now: now,
        isPanelUp: { [weak self] in self?.surface.isPresented ?? false },
        isTakingKeys: { [weak self] in self?.surface.isTakingKeys ?? false },
        // Asked again here rather than trusted from the look just gone: the
        // panel can go down between the two, and asking for the keyboard
        // for one already gone would hand the next keystroke to whatever
        // the user has moved on to.
        takeKeys: { [weak self] in
            guard let self, surface.isPresented else { return false }
            return surface.takeKeys()
        },
        // Dated from the previous look — the earliest the loss could have
        // happened — so the figure covers the whole of the keyboard-less
        // while rather than only the noticing of it.
        onTakenBack: { [weak self] withoutKeys in
            self?.writeLine(
                "panel stopped taking keys; taken back "
                    + "\(Diagnostics.millisecondsText(withoutKeys)) ms later"
            )
        },
        onGaveUp: { [weak self] in
            self?.takeDown(because: "stopped taking keys")
        }
    )

    /// How long the key-status watch waits between looks. Injected only so
    /// a test need not wait a real one out; the number is
    /// `KeyStatusWatch`'s.
    private let keyStatusWatchInterval: Duration

    /// What a commit takes. Owned here rather than by the presenter, for the
    /// same reason the list is: the target is read off the list an appearance
    /// is showing, and both go with the panel.
    private let switcher: any WindowSwitching

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

    /// Whether this appearance may still write a commit line.
    ///
    /// True from the panel going up to it coming down, and false otherwise.
    /// Every commit path asks it after asking whether the panel is up, and
    /// spends it before writing. Looking at the panel alone used to be
    /// enough, because taking it down and spending the commit went together
    /// — but whether the screen still shows the panel is not whether this
    /// appearance has already committed, and a panel that will not come down
    /// when asked would otherwise let one appearance write two commits.
    /// A press called off before any panel appeared is not a commit and
    /// stays outside this flag.
    private var commitIsStillOpen = false

    init(
        surface: any SwitcherSurface,
        now: @escaping @MainActor () -> ContinuousClock.Instant,
        writeLine: @escaping @MainActor (String) -> Void,
        keyStatusWatchInterval: Duration = KeyStatusWatch.defaultInterval,
        switcher: any WindowSwitching = LiveWindowSwitcher(),
        onPanelGone: @escaping @MainActor () -> Void
    ) {
        self.surface = surface
        self.now = now
        self.writeLine = writeLine
        self.keyStatusWatchInterval = keyStatusWatchInterval
        self.switcher = switcher
        self.onPanelGone = onPanelGone
    }

    /// Takes down the list an appearance is showing.
    ///
    /// `startedAt` is the clock read the appearance began with, handed in
    /// so the watch need not take one of its own: the reading below is what
    /// judges how quickly the panel went up, and a read spent here would
    /// land inside its span. As the watch's baseline it errs towards
    /// overstating — the keyboard was last known good when it was asked
    /// for, which is later than the press arriving — and that is the safe
    /// side for a figure about going without.
    func nowShowing(_ windows: [WindowItem], startedAt: ContinuousClock.Instant) {
        presentedWindows = windows
        commitIsStillOpen = true
        // Watched for as long as it is up, and no longer: the looking is
        // started here rather than in the presenter so that whatever puts a
        // panel up gets the looking with it, and stopped where the panel
        // comes down.
        keyWatch.start(knownGoodAt: startedAt)
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
        guard commitIsStillOpen else { return }
        commitIsStillOpen = false
        let target = row(for: id).map { Self.target(of: $0) }
        dismissPanel()
        // Read before switching, so the figure spans the call that hides
        // the panel and none of what follows it.
        let elapsed = now() - startedAt
        switch target {
        case let .some(take):
            record(
                .committed(appName: take.appName, displayTitle: take.displayTitle, id: take.id),
                by: .commandRelease,
                elapsed: elapsed
            )
            // The pair: nothing may come between the two lines, and both
            // carry the same figure, which stops at the panel going away.
            let outcome = switcher.switchTo(take)
            writeLine(SwitchMeasurement(
                appName: take.appName,
                displayTitle: take.displayTitle,
                id: take.id,
                outcome: outcome,
                trigger: .commandRelease,
                elapsed: elapsed
            ).summaryLine)
        case .none:
            record(.nothingToCommit, by: .commandRelease, elapsed: elapsed)
        }
    }

    /// Writes down a press given up on before it ever became a panel.
    ///
    /// Kept apart from a commit over an empty list because the two have
    /// different causes and different answers: one means the list was
    /// gathered and held nothing, the other that there was no list yet.
    func recordPressCalledOff(since startedAt: ContinuousClock.Instant) {
        record(.pressCalledOff, by: .commandRelease, since: startedAt)
    }

    /// Commits the highlighted row for a key that means take this one.
    ///
    /// Reads the row before the panel goes, for the reason a release-driven
    /// commit reads it there: taking the panel down is what throws the list
    /// away, so the reverse order would name a row of nothing. Dismisses
    /// before recording, so the figure covers the call that hides the panel,
    /// the same way round as every other measured exit. An empty list
    /// commits the same way a full one does, except the line says there was
    /// nothing to take — unlike a press called off, which never had a list
    /// at all. Which physical key arrived stays on the line (Return apart
    /// from keypad Enter): that difference is the on-the-run evidence for
    /// going by key code rather than by character.
    func commit(
        by key: CommitKey,
        naming id: WindowItem.Identifier?,
        since startedAt: ContinuousClock.Instant
    ) {
        guard surface.isPresented else { return }
        guard commitIsStillOpen else { return }
        commitIsStillOpen = false
        let target = row(for: id).map { Self.target(of: $0) }
        dismissPanel()
        // Read before switching, for the same reason as above: the figure
        // is about hiding, not about taking.
        let elapsed = now() - startedAt
        switch target {
        case let .some(take):
            record(
                .committed(appName: take.appName, displayTitle: take.displayTitle, id: take.id),
                by: .commitKey(key),
                elapsed: elapsed
            )
            // The pair, as above: adjacent lines, one figure.
            let outcome = switcher.switchTo(take)
            writeLine(SwitchMeasurement(
                appName: take.appName,
                displayTitle: take.displayTitle,
                id: take.id,
                outcome: outcome,
                trigger: .commitKey(key),
                elapsed: elapsed
            ).summaryLine)
        case .none:
            record(.nothingToCommit, by: .commitKey(key), elapsed: elapsed)
        }
    }

    /// Takes the panel down for a key that means not this one.
    ///
    /// Names no row, and the omission is the point. The panel was highlighting
    /// one when the key arrived, and putting its name on this line would read
    /// as that window having been taken — on the one line whose meaning is
    /// that none was. An empty list cancels identically for the same reason:
    /// there was nothing to take either way, so there is nothing to tell the
    /// two apart with.
    ///
    /// Asks nothing before acting, because the one caller has already asked:
    /// a keystroke is only given a meaning while a panel is up. The commit
    /// beside this one does ask, and for a reason this does not share — a
    /// release arrives whether or not a panel is on screen, so it has to turn
    /// away the ones that are somebody finishing a Cmd+C.
    ///
    /// Dismisses before recording, and that order is the measurement. The
    /// figure is meant to cover the call that takes the panel off the screen,
    /// which on a real machine is where the time goes.
    func cancel(by key: CancelKey, since startedAt: ContinuousClock.Instant) {
        dismissPanel()
        record(.cancelled, by: .cancelKey(key), since: startedAt)
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
            PanelExitMeasurement.rowDescription(
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
        commitIsStillOpen = false
        surface.dismiss()
        presentedWindows = []
        keyWatch.stop()
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

    /// The one derivation of what a commit names. The line and the switch
    /// both read off this, so one row cannot be named two ways.
    private static func target(of row: WindowItem) -> ActivationTarget {
        ActivationTarget(
            id: row.id,
            ownerProcessIdentifier: row.ownerProcessIdentifier,
            appName: row.appName,
            displayTitle: row.displayTitle,
            isMinimized: row.isMinimized
        )
    }

    /// Reads the clock after the work, so the figure spans exactly the part
    /// this process is answerable for.
    private func record(
        _ outcome: PanelExitMeasurement.Outcome,
        by trigger: PanelExitMeasurement.Trigger,
        since startedAt: ContinuousClock.Instant
    ) {
        record(outcome, by: trigger, elapsed: now() - startedAt)
    }

    /// The same line with the span handed in, for the paths that act between
    /// hiding and writing. What those paths do stays out of the figure.
    private func record(
        _ outcome: PanelExitMeasurement.Outcome,
        by trigger: PanelExitMeasurement.Trigger,
        elapsed: Duration
    ) {
        let measurement = PanelExitMeasurement(
            outcome: outcome,
            trigger: trigger,
            elapsed: elapsed
        )
        writeLine(measurement.summaryLine)
    }
}
