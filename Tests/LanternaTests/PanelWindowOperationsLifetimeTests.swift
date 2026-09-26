@testable import Lanterna
import Testing

/// An operation outlives the keystroke that started it: its reconciling
/// waits for a fresh list, and the panel can go, or a later one come up,
/// before that list arrives.
@MainActor
struct PanelWindowOperationsLifetimeTests {
    private var rows: [WindowItem] {
        [
            operationRow(appName: "Safari", windowTitle: "Tabs", windowID: 1),
            operationRow(appName: "Safari", windowTitle: "Downloads", windowID: 2),
            operationRow(appName: "Finder", windowTitle: "AirDrop", windowID: 3),
        ]
    }

    /// The panel going while the list is awaited leaves the resumed
    /// reconciling touching nothing: no list swapped in, no choice made
    /// again, no closing, and one line saying it went unreconciled.
    @Test func aPanelGoneMidReconcilingIsLeftAlone() async {
        let rows = rows
        let held = HeldRefresh()
        let made = makeOperations(rows: rows, held: held)
        let running = made.operations.start(.closeWindow, naming: rows[0].id)
        await held.waitUntilAsked()
        made.operations.end()
        made.selection.end()
        made.filter.reset()
        let swapsBefore = made.surface.updatedLists.count
        held.finish(with: Array(rows.dropFirst()))
        await running?.value
        #expect(made.surface.updatedLists.count == swapsBefore)
        #expect(made.selection.chosenID == nil)
        #expect(made.counts.interruptions == 0)
        #expect(made.counts.emptied == 0)
        #expect(made.log.lines.contains { $0.contains("window operation left unreconciled (close Safari/Tabs") })
        #expect(!made.log.lines.contains { $0.contains("window operation (close") })
    }

    /// A later appearance up by the time the list arrives is not the one
    /// the operation set out in, and its rows and choice stay its own.
    @Test func aLaterAppearanceIsLeftAlone() async {
        let rows = rows
        let held = HeldRefresh()
        let made = makeOperations(rows: rows, held: held)
        let running = made.operations.start(.closeWindow, naming: rows[0].id)
        await held.waitUntilAsked()
        made.operations.end()
        let later = [rows[2], rows[1]]
        made.selection.beginSecond(later.map(\.id))
        made.filter.begin(fullWindows: later)
        made.operations.begin(windows: later)
        let swapsBefore = made.surface.updatedLists.count
        held.finish(with: [rows[2]])
        await running?.value
        #expect(made.surface.updatedLists.count == swapsBefore)
        #expect(made.selection.chosenID == rows[1].id)
        #expect(made.counts.interruptions == 0)
    }

    /// A second operation while one is still reconciling is dropped with a
    /// line rather than sent: only the first reaches its application.
    @Test func aSecondOperationWhileOneRunsIsDropped() async {
        let rows = rows
        let held = HeldRefresh()
        let made = makeOperations(rows: rows, held: held)
        let running = made.operations.start(.closeWindow, naming: rows[0].id)
        await held.waitUntilAsked()
        await made.operations.operate(.closeWindow, naming: rows[1].id)
        #expect(made.log.lines.contains { $0.contains("window operation dropped (close") })
        held.finish(with: Array(rows.dropFirst()))
        await running?.value
        #expect(held.askedCount == 1)
        #expect(made.log.lines.contains { $0.contains("window operation (close Safari/Tabs)") })
        #expect(!made.log.lines.contains { $0.contains("Safari/Downloads") })
    }
}
