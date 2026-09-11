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
        writeLine: @escaping @MainActor (String) -> Void = Diagnostics.writeLine
    ) {
        self.surface = surface
        self.store = store
        self.ownProcessIdentifier = ownProcessIdentifier
        self.now = now
        self.writeLine = writeLine
    }

    /// Puts the panel up for a press, or takes it down if the press found it
    /// already up.
    ///
    /// One key does both, so the same key that summons the panel dismisses it
    /// and no second one has to be learned or claimed from the system.
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
            takeDown(because: combination.name)
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

    /// The one place the panel goes away, so the reason is written down every
    /// time and in the same words.
    private func takeDown(because reason: String) {
        surface.dismiss()
        writeLine("panel hidden (\(reason))")
    }
}

/// One press, measured.
///
/// Whether the panel is fast enough is a number, not an impression, and this
/// is where that number is written down. The wording lives with the reading so
/// the two cannot drift apart.
struct HotkeyMeasurement: Sendable {
    let combination: HotkeyCombination
    /// From the press arriving to the call that puts the panel up returning.
    ///
    /// Not the delivery before it and not the compositing after it: a process
    /// can see neither, and a budget that included them could not be checked
    /// from inside.
    let elapsed: Duration
    let entryCount: Int
    /// How long the press spent between being recorded by the system and
    /// arriving here. Observed and reported, but outside the budget above,
    /// because nothing this app does changes it.
    let deliveryDelay: Duration?
    /// Whether the list had to be gathered on the spot, which is the one case
    /// where the reading above says more about the list than about the panel.
    let gatheredOnDemand: Bool

    var summaryLine: String {
        var line = "panel shown \(Diagnostics.millisecondsText(elapsed)) ms "
            + "after \(combination.name) (\(entryCount) entries)"
        if let deliveryDelay {
            line += "; delivery \(Diagnostics.millisecondsText(deliveryDelay)) ms"
        }
        if gatheredOnDemand {
            line += "; gathered on the spot (no list held yet)"
        }
        return line
    }
}
