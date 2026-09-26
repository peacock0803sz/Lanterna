import CoreGraphics
import Darwin

/// Decides when the panel goes up, and writes down what each press cost.
@MainActor
final class PanelPresenter {
    /// Handed on to the way out and the operations, built beside the presenter.
    let surface: any SwitcherSurface
    /// Where the rows come from: already gathered, in the ordinary case.
    let store: WindowListStore
    let displayModes: DisplayModes
    let ownProcessIdentifier: pid_t
    /// Handed on to the way out, built beside the presenter.
    let now: @MainActor () -> ContinuousClock.Instant
    let writeLine: @MainActor (String) -> Void

    /// A press that arrived before any list had been gathered and is waiting
    /// for one.
    ///
    /// `lazy` for the reason the watch below is: what it waits on and what it
    /// does when the waiting is over are both this object's.
    private lazy var pendingPress = PendingPressHold(
        listWhenGathered: { [store] in await store.listWhenGathered() },
        show: { [weak self] items, combination, deliveryDelay, startedAt in
            self?.show(
                items,
                for: combination,
                deliveryDelay: deliveryDelay,
                startedAt: startedAt,
                gatheredOnDemand: true
            )
        }
    )

    /// Whether letting go of Command is what closes the panel.
    ///
    /// Asked on every press rather than settled at launch: the answer can stop
    /// being true under the app, because the system is free to switch a tap off
    /// whenever it likes. A remembered yes would go on spending the very press
    /// that is the way out on moving the selection, leaving a panel whose only
    /// remaining keyboard exits are the cancel keys — which reach it only
    /// where it was granted key status, and which have not been measured
    /// under secure input at all. A run with no monitor answers no throughout.
    private let closesOnCommandRelease: @MainActor () -> Bool

    /// Whether Command is down on the keyboard at this instant.
    ///
    /// Injected rather than read where it is used, because a test process
    /// cannot hold a real Command key down and reading the live state inline
    /// would answer no in every test there is. The decision below turns on
    /// this answer, and a decision that cannot be put either way from a test
    /// is a decision nothing checks.
    private let commandIsHeld: @MainActor () -> Bool

    /// How long the watch waits between looks (`UnreportedReleaseWatch`'s
    /// number, injected so a test need not wait a real one out).
    private let commandWatchInterval: Duration

    /// How long the key-status watch waits between looks (`KeyStatusWatch`'s
    /// number, injected so a test need not wait a real one out), handed on
    /// to the way out, which is built beside the presenter.
    let keyStatusWatchInterval: Duration

    /// What commits take. Through to the way out, which owns the list the
    /// target is read off and is built beside the presenter.
    let switcher: any WindowSwitching

    /// What commits and appearances consult for the order rows are drawn in,
    /// owned here so recording and sorting share one memory.
    let tracker: MRUTracker

    /// The looking that catches a release the tap never reported.
    ///
    /// `lazy` because every question it puts and the answer it gives back are
    /// this object's. One watch for the presenter's life, started and stopped
    /// the way the window list's loop is rather than made again for each panel.
    /// The way out, built beside the presenter, stops it as the panel goes.
    lazy var commandWatch = UnreportedReleaseWatch(
        interval: commandWatchInterval,
        isPanelUp: { [weak self] in self?.surface.isPresented ?? false },
        commandIsHeld: { [weak self] in self?.commandIsHeld() ?? false },
        // The chosen row is read here and not inside the call, because the
        // call is what clears it. Swift settles the argument before the
        // method runs, so the order is the language's rather than a habit.
        onUnreportedRelease: { [weak self] in
            self?.wayOut.closeForAnUnreportedRelease(naming: self?.selection.chosenID)
        }
    )

    /// Which row of the list on screen is chosen.
    ///
    /// Kept apart from the list it indexes, and the line is drawn where it is
    /// on purpose: `PanelExit` names rows, and naming is not choosing. Given
    /// up where the panel comes off the screen rather than at each way out,
    /// so no way out can be the one that forgets.
    /// That giving up is wired into the way out, built beside the presenter.
    let selection: PanelSelection

    /// Every way the panel comes off the screen, and the list it was showing
    /// while it was up.
    ///
    /// `lazy` for the reason the watch above is: what it does when the panel
    /// goes reaches back into this object.
    ///
    /// Built by a function rather than written out here, because these two
    /// name each other — the watch reports a release to the way out, and the
    /// way out stops the watch — and two `lazy` properties whose types are
    /// both left to be worked out from expressions naming the other cannot
    /// be worked out at all. A declared return type settles one of them, and
    /// the other follows. Spelling the type on the property instead would say
    /// the same thing, and the formatter would take it straight back off
    /// again as a repetition of the initialiser beside it.
    /// The operations, built beside the presenter, close the panel through it.
    lazy var wayOut = makeWayOut()

    /// What a press means to a panel that is up.
    ///
    /// `lazy` because it is handed the way out, which is itself `lazy`. It
    /// holds nothing of its own — the panel, the chosen row and the ways out
    /// are all this object's — so the two can share them rather than keep
    /// second copies.
    /// The way out and the operations, built beside the presenter, reach it.
    lazy var keyCommands = PanelKeyCommands(
        surface: surface,
        selection: selection,
        wayOut: wayOut,
        displayModes: displayModes,
        now: now,
        operate: { [weak self] operation, chosen in
            self?.startOperation(operation, naming: chosen)
        }
    )

    /// Carries out the operations on the chosen row. Made beside the
    /// presenter, so no two `lazy` properties name each other.
    lazy var operations = makeOperations()

    init(
        surface: any SwitcherSurface,
        store: WindowListStore,
        displayModes: DisplayModes = .defaults,
        ownProcessIdentifier: pid_t = getpid(),
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        writeLine: @escaping @MainActor (String) -> Void = Diagnostics.writeLine,
        closesOnCommandRelease: @escaping @MainActor () -> Bool = { false },
        commandIsHeld: @escaping @MainActor () -> Bool = {
            CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
        },
        commandWatchInterval: Duration = UnreportedReleaseWatch.defaultInterval,
        keyStatusWatchInterval: Duration = KeyStatusWatch.defaultInterval,
        switcher: any WindowSwitching = LiveWindowSwitcher(),
        tracker: MRUTracker = MRUTracker()
    ) {
        self.surface = surface
        selection = PanelSelection(surface: surface)
        self.store = store
        self.displayModes = displayModes
        self.ownProcessIdentifier = ownProcessIdentifier
        self.now = now
        self.writeLine = writeLine
        self.closesOnCommandRelease = closesOnCommandRelease
        self.commandIsHeld = commandIsHeld
        self.commandWatchInterval = commandWatchInterval
        self.keyStatusWatchInterval = keyStatusWatchInterval
        self.switcher = switcher
        self.tracker = tracker
    }

    /// Puts the panel up for a press, and takes it down again if the press
    /// found one already up and letting go of Command is not what will close
    /// it. That is three of the four states enumerated below, not only the
    /// run with no monitor.
    ///
    /// That second job is a fallback now rather than the design. One key doing
    /// both was what dismissed the panel without a second key having to be
    /// learned or claimed from the system; where letting go of Command does
    /// the dismissing, a further press moves the selection along instead,
    /// which is the keystroke the user reaches for anyway while the key is
    /// still down.
    ///
    /// Nothing here turns a press away for arriving too soon after the last
    /// one. Holding the key down does not produce a stream of presses: three
    /// seconds on Cmd+Tab yielded exactly one. That was measured while this
    /// method could only put the panel up, so a repeat would have shown as a
    /// second panel rather than as a flicker, and the reading cannot be a
    /// toggle racing itself. A suppression window would have nothing to
    /// suppress, at the price of a stored instant and a threshold.
    ///
    /// Synchronous on purpose. With a list already held the panel goes up in
    /// the same turn the press arrives, so the reading below starts where the
    /// press does and there is no ordering between a press and its panel to
    /// reason about.
    func handleHotkey(_ combination: HotkeyCombination, deliveryDelay: Duration?) {
        // Read before anything else, because both questions below are put to
        // the window server rather than answered in this process. A span begun
        // after them would leave out work this process is answerable for, and
        // would quietly shrink as anything further moved ahead of the read
        // while the figure went on reading the same. A press that is turned
        // away writes no line at all, so charging it a clock read costs
        // nothing.
        let startedAt = now()
        if surface.isPresented {
            // Two questions, and the four states they make between them. Is
            // a monitor running, and was this appearance given a watch.
            //
            // Both yes, and the press moves the selection: letting go of
            // Command is what will close the panel, so this keystroke is
            // free to mean something else.
            //
            // Any other pair, and the press is what closes the panel,
            // because nothing else will. No monitor ever started, and there
            // is no release being listened for at all. A monitor that was
            // stopped when the panel went up left this appearance without a
            // watch, and one that has come back since takes its idea of the
            // modifiers from the keyboard as it finds it — a Command let go
            // meanwhile leaves it no release to report. A monitor that has
            // stopped since the panel went up leaves a watch still looking
            // with nothing left to report to it.
            //
            // So the split is neither question on its own. The middle two
            // states differ from the first in one of them each, and both are
            // read again on every press because either can have changed
            // since the last.
            let pressMovesTheSelection = closesOnCommandRelease() && commandWatch.isLooking
            guard pressMovesTheSelection || combination == .filter else {
                wayOut.takeDown(because: combination.name)
                return
            }
            switch combination {
            case .forward:
                selection.moveToNext()
            case .reverse:
                selection.moveToPrevious()
            case .filter:
                keyCommands.activateFiltering()
                commandWatch.stop()
            }
            return
        }
        // The press comes in through Carbon and the release through the tap,
        // two sources with no order between them and a measured delay on the
        // Carbon side, so a quick tap can deliver the release first and leave
        // the press arriving after the gesture it belongs to is over. Putting
        // a panel up for it would leave one on screen the user has finished
        // with, and the next Command to be let go — a bare tap, the tail of a
        // Cmd+C — would be written down as a commit of a row nobody chose.
        // Only worth asking with a monitor running: without one there is no
        // release being listened for and so none to lose, and the panel is
        // still closed by a further press.
        //
        // Asked as the press arrives and not where the panel goes up, because
        // a press held back waiting for the first list can lose its Command
        // too, and that one is already answered — the release calls the
        // pending press off. Here is what nothing else covers.
        if closesOnCommandRelease(), !commandIsHeld() {
            writeLine(
                "turned away \(combination.name); Command was already up by the time "
                    + "the press arrived"
            )
            return
        }
        // A press is already waiting for the first list and is the one that
        // will put the panel up. The panel is not up yet, so without this a
        // second press would take the same path again and two would arrive.
        guard !pendingPress.isWaiting else { return }
        guard let held = store.snapshot else {
            pendingPress.begin(combination, deliveryDelay: deliveryDelay, startedAt: startedAt)
            return
        }
        show(
            held.items,
            for: combination,
            deliveryDelay: deliveryDelay,
            startedAt: startedAt,
            gatheredOnDemand: false
        )
    }

    /// The one place the panel goes up, so every appearance is measured and
    /// every measurement describes an appearance.
    private func show(
        _ windows: [WindowItem],
        for combination: HotkeyCombination,
        deliveryDelay: Duration?,
        startedAt: ContinuousClock.Instant,
        gatheredOnDemand: Bool
    ) {
        // Five orderings below are load-bearing, and the statements they
        // hold apart are named one pair at a time rather than counted.
        //
        // The list is ordered first, so everything this appearance shows,
        // names, and measures reads off one value no later refresh can move.
        //
        // The cursor is made next, so that what the panel is told to draw is
        // read off it. The filter starts beside it, over the same ordered
        // list, so the first keystroke narrows what the panel was shown.
        //
        // Keys are asked for after the panel is up and before the reading:
        // a window that is not on screen cannot become the key window, and
        // a press the keyboard never reached did not finish its work.
        //
        // Handing the list to the way out is the one statement here whose
        // position is free: it has to happen before the panel can go.
        tracker.noteSnapshotObserved(store.snapshot?.gatheredAt ?? now())
        let ordered = tracker.ordered(windows, skipping: store.snapshot?.skippedOwners ?? [])
        selection.beginSecond(ordered.map(\.id))
        keyCommands.beginFiltering(fullWindows: ordered, filtering: combination == .filter)
        operations.begin(windows: ordered)
        surface.present(windows: ordered, selecting: selection.chosenID)
        let becameKey = surface.takeKeys()
        wayOut.nowShowing(ordered, startedAt: startedAt)
        let measurement = HotkeyMeasurement(
            combination: combination,
            elapsed: now() - startedAt,
            entryCount: ordered.count,
            deliveryDelay: deliveryDelay,
            gatheredOnDemand: gatheredOnDemand,
            becameKey: becameKey,
            mru: MRUSummary(firstID: ordered.first?.id, source: tracker.newestSource)
        )
        writeLine(measurement.summaryLine)

        // Only with a monitor is a release expected at all, and starting below
        // the reading is what keeps the task out of the figure. Filtering starts
        // no watch, for releases end nothing there. The key-status looking starts
        // with the handover above: it lasts as long as the panel does, and the
        // way out owns both ends of that.
        if closesOnCommandRelease(), !keyCommands.isFilteringActive {
            commandWatch.start()
        }
    }

    /// Takes the panel down when an application other than this one comes to
    /// the front, which is the user having moved on to something else.
    ///
    /// Every activation is announced, so most calls arrive with no panel up
    /// and must do nothing at all.
    ///
    /// This process is ruled out rather than assumed absent. The panel can
    /// take key status now, which is the part of this that changed, and
    /// taking it was measured not to bring the application forward: over
    /// twenty appearances no notification named this process, the frontmost
    /// application never changed, and the application never reported itself
    /// active. The reading is not an instrument that failed to fire, because
    /// a control that brought another application forward on purpose was
    /// announced both times.
    ///
    /// So a notification naming this process is not expected — and it is
    /// still compared for, because acting on one that did arrive would take a
    /// panel down the moment it appeared, or throw away a press still on its
    /// way to becoming one. One comparison is a cheap way never to find out
    /// the hard way.
    func handleActivation(of processIdentifier: pid_t) {
        guard processIdentifier != ownProcessIdentifier else { return }
        if pendingPress.isWaiting {
            // Nothing is on screen to take down. What has to stop is the
            // panel still on its way, which would otherwise appear over
            // whatever the user has just turned to. The line is for the press
            // and not for the panel: the press is what the user did, and one
            // that disappeared without a word could not be told from one that
            // never arrived at all. Written plainly rather than measured,
            // because every figure in these lines runs from something the
            // user did to this process answering it — a release, or one of
            // the keys that end an appearance — and nothing of the kind
            // happened here. The frontmost application changed on its own.
            pendingPress.callOff()
            writeLine(
                "called off the press waiting for its first list; "
                    + "the frontmost application changed"
            )
            return
        }
        guard surface.isPresented else { return }
        wayOut.takeDown(because: "frontmost application changed")
    }

    /// Hands a key press to the one place that decides what becomes of it,
    /// kept as an entry because the channel is wired to the presenter.
    func handleKeyStroke(_ keystroke: PanelKeystroke) -> PanelKeyDisposition {
        keyCommands.handle(keystroke)
    }

    /// Acts on Command having been let go.
    ///
    /// The press waiting for its first list is asked about first, and the
    /// order carries weight. Such a press means the panel is not up, so
    /// asking whether it is up first would send that case down the quiet path
    /// and leave the press to arrive as a panel over whatever the user had
    /// turned to. Letting the slot go is what stops it.
    func handleCommandRelease() {
        let startedAt = now()
        if pendingPress.isWaiting {
            pendingPress.callOff()
            wayOut.recordPressCalledOff(since: startedAt)
            return
        }
        guard !keyCommands.isFilteringActive else { return }
        wayOut.commitOnCommandRelease(naming: selection.chosenID, since: startedAt, filter: keyCommands.filterSummary())
    }
}
