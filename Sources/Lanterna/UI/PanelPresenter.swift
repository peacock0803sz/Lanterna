import CoreGraphics
import Darwin

/// The panel as the code deciding when to show it sees it: something that can
/// be put up with a list, taken down, and asked whether it is up.
///
/// It is behind a protocol because a real panel needs a window server, which
/// a test process has no business asking for. Whether it is up is asked of the
/// panel rather than tracked alongside it: two records of one thing are two
/// things that can disagree.
@MainActor
protocol SwitcherSurface {
    var isPresented: Bool { get }
    func present(windows: [WindowItem])
    func dismiss()
}

extension SwitcherPanel: SwitcherSurface {}

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
    /// Kept here rather than read back off the store. The task that does the
    /// waiting does not begin the instant it is made, and a second press
    /// landing in that gap would find the store idle and start a second wait.
    private var pendingPress: PendingPress?

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

    /// The row the panel is showing as selected, kept so a commit can name it.
    ///
    /// `displayTitle` and not `windowTitle`: the latter may be empty or hold
    /// nothing but whitespace, and the panel shows the application's name in
    /// that case. A line disagreeing with the panel would be worse than no
    /// line. The selection does not move yet, so this is the first row of
    /// whatever was presented.
    private var selectedWindow: (appName: String, displayTitle: String)?

    private struct PendingPress {
        let combination: HotkeyCombination
        let deliveryDelay: Duration?
        /// When the press arrived. The reading spans the gathering too, which
        /// is why the line it produces says the gathering happened.
        let startedAt: ContinuousClock.Instant
    }

    init(
        surface: any SwitcherSurface,
        store: WindowListStore,
        ownProcessIdentifier: pid_t = getpid(),
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        writeLine: @escaping @MainActor (String) -> Void = Diagnostics.writeLine,
        closesOnCommandRelease: @escaping @MainActor () -> Bool = { false },
        commandIsHeld: @escaping @MainActor () -> Bool = {
            CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
        }
    ) {
        self.surface = surface
        self.store = store
        self.ownProcessIdentifier = ownProcessIdentifier
        self.now = now
        self.writeLine = writeLine
        self.closesOnCommandRelease = closesOnCommandRelease
        self.commandIsHeld = commandIsHeld
    }

    /// Puts the panel up for a press, and on a run with no monitor takes it
    /// down again if the press found it already up.
    ///
    /// That second job is a fallback now rather than the design. One key doing
    /// both was what dismissed the panel without a second key having to be
    /// learned or claimed from the system; with a monitor running, letting go
    /// of Command does the dismissing and a further press does nothing at all,
    /// because that keystroke is spoken for by the step that lets the
    /// selection move.
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
        if surface.isPresented {
            // This is where the panel closes whenever no monitor is running
            // just then — one never started, or one has stopped. With one
            // running, Command's release closes the panel and this keystroke
            // is the one that will move the selection along — so it does
            // nothing rather than something that would have to be taken back.
            guard !closesOnCommandRelease() else { return }
            takeDown(because: combination.name)
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
        guard pendingPress == nil else { return }

        let startedAt = now()
        guard let held = store.snapshot else {
            waitForTheFirstList(combination, deliveryDelay: deliveryDelay, startedAt: startedAt)
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

    /// Holds the press until there is a list, then puts the panel up for it.
    ///
    /// Only a press arriving before the loop's first pass completes can get
    /// here. The task below carries none of the press with it; it is a
    /// standing "wake me once a list exists", and every field it shows the
    /// panel with is read out of `pendingPress` at the moment it resumes.
    /// That is what makes two such tasks interchangeable: when a press is
    /// called off and another takes its place, whichever task wakes first
    /// finds the press that is really waiting and puts the panel up for it,
    /// and the other finds the slot empty and does nothing.
    private func waitForTheFirstList(
        _ combination: HotkeyCombination,
        deliveryDelay: Duration?,
        startedAt: ContinuousClock.Instant
    ) {
        pendingPress = PendingPress(
            combination: combination,
            deliveryDelay: deliveryDelay,
            startedAt: startedAt
        )
        Task { [self] in
            let items = await store.listWhenGathered()
            guard let pending = pendingPress else { return }
            pendingPress = nil
            show(
                items,
                for: pending.combination,
                deliveryDelay: pending.deliveryDelay,
                startedAt: pending.startedAt,
                gatheredOnDemand: true
            )
        }
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
        surface.present(windows: windows)
        // Read here rather than off the panel at commit time, so what the
        // commit names is the list this appearance was given. The selection
        // stays on the first row for as long as nothing can move it.
        selectedWindow = windows.first.map {
            (appName: $0.appName, displayTitle: $0.displayTitle)
        }
        let measurement = HotkeyMeasurement(
            combination: combination,
            elapsed: now() - startedAt,
            entryCount: windows.count,
            deliveryDelay: deliveryDelay,
            gatheredOnDemand: gatheredOnDemand
        )
        writeLine(measurement.summaryLine)
    }

    /// Takes the panel down when an application other than this one comes to
    /// the front, which is the user having moved on to something else.
    ///
    /// Every activation is announced, so most calls arrive with no panel up
    /// and must do nothing at all.
    ///
    /// This process is ruled out rather than assumed absent. The panel is
    /// built not to activate it — non-activating, neither key nor main,
    /// ordered front regardless — so a notification naming this process is not
    /// expected; acting on one that did arrive would take a panel down the
    /// moment it appeared, or throw away a press still on its way to becoming
    /// one, and one comparison is a cheap way never to find out the hard way.
    func handleActivation(of processIdentifier: pid_t) {
        guard processIdentifier != ownProcessIdentifier else { return }
        if pendingPress != nil {
            // Nothing is on screen to take down. What has to stop is the
            // panel still on its way, which would otherwise appear over
            // whatever the user has just turned to, and letting the slot go
            // is what stops it. It also leaves the way clear for whatever
            // comes next: while the slot is occupied every press is turned
            // away as the duplicate of one already being answered, so a press
            // arriving before the list does would be dropped rather than
            // shown. No line either: the panel never appeared, so there is no
            // appearance to account for.
            pendingPress = nil
            return
        }
        guard surface.isPresented else { return }
        takeDown(because: "frontmost application changed")
    }

    /// Acts on Command having been let go.
    ///
    /// The three questions are asked in this order, and the order carries
    /// weight. A press still waiting for its first list means the panel is not
    /// up, so asking whether it is up first would send that case down the
    /// quiet path and leave the press to arrive as a panel over whatever the
    /// user had turned to. Letting the slot go is what stops it.
    ///
    /// With no panel and nothing pending, the release is somebody finishing a
    /// Cmd+C, and nothing is said. A log with a line per keystroke is a log
    /// nobody reads.
    func handleCommandRelease() {
        let startedAt = now()
        if pendingPress != nil {
            pendingPress = nil
            record(.pressCalledOff, since: startedAt)
            return
        }
        guard surface.isPresented else { return }

        // Read before the panel goes, because taking it down is what clears
        // the selection.
        let outcome: CommandReleaseMeasurement.Outcome = selectedWindow.map {
            .committed(appName: $0.appName, displayTitle: $0.displayTitle)
        } ?? .nothingToCommit
        dismissPanel()
        record(outcome, since: startedAt)
    }

    /// The one place the panel comes off the screen.
    ///
    /// This used to be able to say more: `takeDown(because:)` was the only way
    /// the panel went away, so every disappearance wore the same wording. A
    /// commit is a second way out, and it words its own line, so what holds
    /// now is the weaker invariant: every time the panel goes, exactly one
    /// line says why. Saying it twice would be no better than not at all —
    /// counting the lines afterwards would find two events where the user saw
    /// one.
    ///
    /// The selection goes with the panel. Nothing reads it while the panel is
    /// down, so no sequence of calls can tell whether this line is here —
    /// it is kept because a row outliving the panel it was on is the kind of
    /// thing a later step, where the selection does move, would find already
    /// wrong.
    private func dismissPanel() {
        surface.dismiss()
        selectedWindow = nil
    }

    /// The wording for the two disappearances that are the app tidying up
    /// after itself rather than the user deciding anything.
    private func takeDown(because reason: String) {
        dismissPanel()
        writeLine("panel hidden (\(reason))")
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
