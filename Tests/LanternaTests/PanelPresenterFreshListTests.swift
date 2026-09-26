@testable import Lanterna
import Testing

/// A pass that found the given rows.
@MainActor
private func passFinding(_ items: [WindowItem]) -> WindowListSnapshot {
    WindowListSnapshot(
        items: items,
        applicationCount: Set(items.map(\.ownerProcessIdentifier)).count,
        gatheringDuration: .milliseconds(12),
        skipped: [],
        droppedWithoutID: 0,
        gatheredAt: .now
    )
}

/// The list reconciling reads while a panel is up: in the order the
/// appearance draws, and read without deciding what counts as gone.
@MainActor
struct PanelPresenterFreshListTests {
    private var rows: [WindowItem] {
        [
            operationRow(appName: "Safari", windowTitle: "Tabs", windowID: 1, pid: 123),
            operationRow(appName: "Mail", windowTitle: "Inbox", windowID: 2, pid: 124),
            operationRow(appName: "Finder", windowTitle: "AirDrop", windowID: 3, pid: 125),
        ]
    }

    /// A fresh list comes back newest first, the way the appearance drew
    /// it, so a place counted in one reads the same in the other.
    @Test func aFreshListComesBackInTheDrawnOrder() async {
        let rows = rows
        let tracker = MRUTracker()
        tracker.record(rows[2].id, ownerProcessIdentifier: rows[2].ownerProcessIdentifier, origin: .external)
        let presenter = PanelPresenter(
            surface: FakeSurface(),
            store: WindowListStore(gather: { passFinding(rows) }, writeLine: { _ in }),
            writeLine: { _ in },
            tracker: tracker
        )
        let fresh = await presenter.freshList()
        #expect(fresh.map(\.id) == [rows[2].id, rows[0].id, rows[1].id])
    }

    /// Sorting a list read mid-appearance sweeps nothing: a record the list
    /// leaves out, old enough for a sweep to take, is still there after.
    @Test func arrangingSweepsNothing() {
        let rows = rows
        let tracker = MRUTracker(now: SteppingClock(step: .seconds(4)).read)
        tracker.record(rows[0].id, ownerProcessIdentifier: rows[0].ownerProcessIdentifier, origin: .external)
        _ = tracker.arranged([rows[1]])
        #expect(tracker.newestSource == .external)
        #expect(tracker.arranged([rows[1], rows[0]]).map(\.id) == [rows[0].id, rows[1].id])
    }
}
