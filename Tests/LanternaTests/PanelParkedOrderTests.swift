@testable import Lanterna
import Testing

/// Parked rows sit below the separator, and the list everyone counts in
/// has them there too: the second row an appearance opens on, the place an
/// operation's choice lands on, and the arrows all step through the rows in
/// the order the panel draws them.
@MainActor
struct PanelParkedOrderTests {
    private var rows: [WindowItem] {
        [
            operationRow(appName: "Safari", windowTitle: "Tabs", windowID: 1, pid: 123),
            operationRow(appName: "Mail", windowTitle: "Inbox", windowID: 2, pid: 124).settingHidden(true),
            operationRow(appName: "Finder", windowTitle: "AirDrop", windowID: 3, pid: 125),
        ]
    }

    /// An appearance opens on the second row the panel draws: a parked row
    /// between two rows in use goes below the separator, and the choice
    /// opens on the row in use after the first.
    @Test func theSecondRowIsTheNextRowInUse() {
        let rows = rows
        let fixture = Fixture(store: WindowListStore(fixed: rows), windows: rows)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        #expect(fixture.surface.presentedLists.last?.map(\.id) == [rows[0].id, rows[2].id, rows[1].id])
        #expect(fixture.surface.presentedSelections.last == rows[2].id)
    }

    /// Closing the row above a parked group hands the choice to the next
    /// row in use, not to a parked row the list once held between them.
    /// The arrows then cross the separator where the panel draws it.
    @Test func closingAboveAParkedGroupChoosesTheNextRowInUse() async {
        let rows = rows
        let shown = MRUTracker().arranged(rows)
        let made = makeOperations(rows: shown, refreshed: MRUTracker().arranged([rows[1], rows[2]]))
        made.selection.retarget(to: shown.map(\.id), selecting: rows[0].id)
        await made.operations.operate(.closeWindow, naming: rows[0].id)
        #expect(made.surface.updatedLists.last?.map(\.id) == [rows[2].id, rows[1].id])
        #expect(made.selection.chosenID == rows[2].id)
        made.selection.moveToNext()
        #expect(made.selection.chosenID == rows[1].id)
    }

    /// Minimizing moves the row below the separator at once, before any
    /// pass confirms it, into the minimized subgroup under the hidden-app
    /// one, and the choice stays at the place the row left: the next row
    /// in use takes it. It holds the refresh, so it carries a
    /// time limit for a run that never asks for the list.
    @Test(.timeLimit(.minutes(1))) func minimizingMovesTheRowBelowAtOnce() async {
        let rows = rows
        let shown = MRUTracker().arranged(rows)
        let held = HeldRefresh()
        let made = makeOperations(rows: shown, held: held)
        made.selection.retarget(to: shown.map(\.id), selecting: rows[0].id)
        guard let running = made.operations.start(.minimizeWindow, naming: rows[0].id) else {
            Issue.record("the operation was dropped")
            return
        }
        await held.waitUntilAsked()
        let optimistic = made.surface.updatedLists.last ?? []
        #expect(optimistic.map(\.id) == [rows[2].id, rows[1].id, rows[0].id])
        #expect(optimistic.map(\.isParked) == [false, true, true])
        #expect(made.selection.chosenID == rows[2].id)
        held.finish(with: MRUTracker().arranged([rows[0].settingMinimized(true), rows[1], rows[2]]))
        await running.value
        #expect(made.selection.chosenID == rows[2].id)
    }
}
