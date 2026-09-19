import CoreGraphics
import Darwin

/// Decides when the panel goes up, and writes down what each press cost.
@MainActor
final class PanelPresenter {
    private let surface: any SwitcherSurface
    /// Where the rows come from: already gathered, in the ordinary case.
    private let store: WindowListStore
    private let ownProcessIdentifier: pid_t
    private let now: @MainActor () -> ContinuousClock.Instant
    private let writeLine: @MainActor (String) -> Void

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
    /// whenever it likes. A remembered yes would go on turning away the very
    /// press that is the way out, leaving a panel nothing on the keyboard can
    /// close. A run with no monitor answers no throughout.
    private let closesOnCommandRelease: @MainActor () -> Bool

    /// Whether Command is down on the keyboard at this instant.
    ///
    /// Injected rather than read where it is used, because a test process
    /// cannot hold a real Command key down and reading the live state inline
    /// would answer no in every test there is. The decision below turns on
    /// this answer, and a decision that cannot be put either way from a test
    /// is a decision nothing checks.
    private let commandIsHeld: @MainActor () -> Bool

    /// How long the watch waits between looks. Injected only so a test need
    /// not wait a real one out; the number is `UnreportedReleaseWatch`'s.
    private let commandWatchInterval: Duration

    /// The looking that catches a release the tap never reported.
    ///
    /// `lazy` because every question it puts and the answer it gives back are
    /// this object's, and a closure over `self` cannot be written until the
    /// stored properties are in place. One watch for the presenter's life,
    /// started and stopped the way the window list's loop is rather than made
    /// again for each panel.
    private lazy var commandWatch = UnreportedReleaseWatch(
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
    private let selection: PanelSelection

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
    private lazy var wayOut = makeWayOut()

    init(
        surface: any SwitcherSurface,
        store: WindowListStore,
        ownProcessIdentifier: pid_t = getpid(),
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        writeLine: @escaping @MainActor (String) -> Void = Diagnostics.writeLine,
        closesOnCommandRelease: @escaping @MainActor () -> Bool = { false },
        commandIsHeld: @escaping @MainActor () -> Bool = {
            CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
        },
        commandWatchInterval: Duration = UnreportedReleaseWatch.defaultInterval
    ) {
        self.surface = surface
        selection = PanelSelection(surface: surface)
        self.store = store
        self.ownProcessIdentifier = ownProcessIdentifier
        self.now = now
        self.writeLine = writeLine
        self.closesOnCommandRelease = closesOnCommandRelease
        self.commandIsHeld = commandIsHeld
        self.commandWatchInterval = commandWatchInterval
    }

    private func makeWayOut() -> PanelExit {
        PanelExit(
            surface: surface,
            now: now,
            writeLine: writeLine,
            onPanelGone: { [weak self] in
                self?.commandWatch.stop()
                self?.selection.end()
            }
        )
    }

    /// Puts the panel up for a press, and on a run with no monitor takes it
    /// down again if the press found it already up.
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
            guard pressMovesTheSelection else {
                wayOut.takeDown(because: combination.name)
                return
            }
            switch combination {
            case .forward:
                selection.moveToNext()
            case .reverse:
                selection.moveToPrevious()
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
        // Four steps, and the order of all four is the point.
        //
        // The cursor is made first, so that what the panel is told to draw is
        // read off it. The first row was worked out twice over until now —
        // once here and once inside the panel — and two derivations of one
        // thing agreed only because nothing could move the choice. Passing
        // `windows.first?.id` here instead would leave the second derivation
        // standing beside the cursor, agreeing with it, until the day it did
        // not.
        //
        // Keys are asked for after the panel is up, because a window that is
        // not on screen cannot become the key window, and before the reading
        // is taken, because a press that put a panel up the keyboard never
        // reached is a press that did not finish its work.
        selection.begin(windows.map(\.id))
        surface.present(windows: windows, selecting: selection.chosenID)
        let becameKey = surface.takeKeys()
        wayOut.nowShowing(windows)
        let measurement = HotkeyMeasurement(
            combination: combination,
            elapsed: now() - startedAt,
            entryCount: windows.count,
            deliveryDelay: deliveryDelay,
            gatheredOnDemand: gatheredOnDemand,
            becameKey: becameKey
        )
        writeLine(measurement.summaryLine)

        // Only with a monitor is a release expected at all, and starting below
        // the reading is what keeps the task out of the figure.
        if closesOnCommandRelease() {
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
            // because every figure in these lines is a span since Command was
            // released, and no release happened here.
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

    /// Decides what becomes of a key press.
    ///
    /// With no panel up the press is nothing to do with this app, and it goes
    /// on to whatever would have had it. This is the only place that question
    /// is asked: the channel delivering the press keeps no idea of whether a
    /// panel is up, because two records of that are two things that can
    /// disagree.
    ///
    /// With a panel up, everything is swallowed — the keys that mean
    /// something here and equally the ones that mean nothing. The middle
    /// course of handing back only the keys with no meaning was considered
    /// and is wrong twice over. An event handed back travels the responder
    /// chain, and the SDK says plainly what waits at the end of it: a key
    /// press nothing handles rings the system alert. And a character key
    /// passed on would type into whatever is in front, so a panel that is up
    /// would be filling somebody's document while it stood there.
    ///
    /// What the press meant does not change that answer. It decides what
    /// happens here, and every case leaves by the same door.
    ///
    /// The cases with nothing under them are written out rather than swept up
    /// by a `default`, so that the step which gives one of them a body is
    /// made to come here and find it.
    func handleKeyStroke(_ keystroke: PanelKeystroke) -> PanelKeyDisposition {
        // Read before the key is even given a meaning, because giving it one
        // is work done in answer to the press and the span is meant to cover
        // everything this process does about it. A span begun after the
        // mapping would quietly shrink as anything further moved ahead of the
        // read while the figure went on reading the same — the reason the
        // press that puts a panel up is charged its clock read first too.
        //
        // Every press pays for the read, including the ones that write no
        // line. A press with no panel up costs the same and is the reason the
        // read sits above the guard rather than below it: a keystroke this
        // app decided not to answer took time to decide that.
        let startedAt = now()
        guard surface.isPresented else { return .passedThrough }
        switch PanelKeyInput.action(for: keystroke) {
        case .selectNext:
            selection.moveToNext()
        case .selectPrevious:
            selection.moveToPrevious()
        case let .cancel(key):
            wayOut.cancel(by: key, since: startedAt)
        case .commit, .absorb:
            break
        }
        return .absorbed
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
        wayOut.commitOnCommandRelease(naming: selection.chosenID, since: startedAt)
    }
}
