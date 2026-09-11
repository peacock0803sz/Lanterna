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
    /// Where the rows come from.
    ///
    /// Called on the press and answered synchronously, which is a stopgap. An
    /// application that has stopped answering makes a pass take about a
    /// second, and right now the press is what waits for it, so the timing
    /// this class reports is not yet a timing anyone should rely on. Handing
    /// over a list gathered in the background is what fixes that, and this is
    /// where it goes.
    private let gather: @MainActor () -> [WindowItem]
    private let now: @MainActor () -> ContinuousClock.Instant
    private let writeLine: @MainActor (String) -> Void

    init(
        surface: any SwitcherSurface,
        gather: @escaping @MainActor () -> [WindowItem],
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        writeLine: @escaping @MainActor (String) -> Void = Diagnostics.writeLine
    ) {
        self.surface = surface
        self.gather = gather
        self.now = now
        self.writeLine = writeLine
    }

    /// Puts the panel up for a press, or takes it down if the press found it
    /// already up.
    ///
    /// One key does both, so the same key that summons the panel dismisses it
    /// and no second one has to be learned or claimed from the system.
    ///
    /// Synchronous on purpose. The panel goes up in the same turn the press
    /// arrives, so the reading below starts where the press does and there is
    /// no ordering between a press and its panel to reason about.
    func handleHotkey(_ combination: HotkeyCombination, deliveryDelay: Duration?) {
        if surface.isPresented {
            surface.dismiss()
            writeLine("panel hidden (\(combination.name))")
            return
        }

        let startedAt = now()
        let windows = gather()
        surface.present(windows: windows)
        let measurement = HotkeyMeasurement(
            combination: combination,
            elapsed: now() - startedAt,
            entryCount: windows.count,
            deliveryDelay: deliveryDelay,
            // No list is held anywhere yet, so every press gathers its own.
            // The segment stops appearing once one is.
            gatheredOnDemand: true
        )
        writeLine(measurement.summaryLine)
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
