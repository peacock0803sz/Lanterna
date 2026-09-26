import Darwin
@testable import Lanterna
import Testing

/// A pass that found the given rows, timing out on the skipped owners.
@MainActor
private func passFinding(_ items: [WindowItem], skipping skipped: [pid_t] = []) -> WindowListSnapshot {
    WindowListSnapshot(
        items: items,
        applicationCount: Set(items.map(\.ownerProcessIdentifier)).count + skipped.count,
        gatheringDuration: .milliseconds(12),
        skipped: skipped.map { .init(name: "Busy", reason: .timedOut, processIdentifier: $0) },
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
        let fresh = await presenter.freshList(carrying: [])
        #expect(fresh?.windows.map(\.id) == [rows[2].id, rows[0].id, rows[1].id])
    }

    /// A parked row comes back at its recent-use place: where it draws is
    /// the filter's to decide, by the display modes, as it draws.
    @Test func aFreshListLeavesParkedRowsAtTheirRecentUsePlace() async {
        let rows = [self.rows[0].settingHidden(true), self.rows[1], self.rows[2]]
        let tracker = MRUTracker()
        tracker.record(rows[0].id, ownerProcessIdentifier: rows[0].ownerProcessIdentifier, origin: .external)
        let presenter = PanelPresenter(
            surface: FakeSurface(),
            store: WindowListStore(gather: { passFinding(rows) }, writeLine: { _ in }),
            writeLine: { _ in },
            tracker: tracker
        )
        let fresh = await presenter.freshList(carrying: [])
        #expect(fresh?.windows.map(\.id) == [rows[0].id, rows[1].id, rows[2].id])
    }

    /// Rows of an application the pass could not read are carried over
    /// from the list shown before, and the application is named as
    /// skipped, so neither the panel nor the reconciling reads its rows as
    /// gone.
    @Test func aSkippedApplicationsRowsAreCarriedOver() async {
        let rows = rows
        let presenter = PanelPresenter(
            surface: FakeSurface(),
            store: WindowListStore(gather: { passFinding([rows[0]], skipping: [125]) }, writeLine: { _ in }),
            writeLine: { _ in }
        )
        let fresh = await presenter.freshList(carrying: rows)
        #expect(fresh?.windows.map(\.id) == [rows[0].id, rows[2].id])
        #expect(fresh?.skippedOwners == [125])
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

    /// Reading a fresh list sweeps nothing either: a record the pass leaves
    /// out, old enough for a sweep to take, is still there after.
    @Test func aFreshListSweepsNothing() async {
        let rows = rows
        let tracker = MRUTracker(now: SteppingClock(step: .seconds(4)).read)
        tracker.record(rows[0].id, ownerProcessIdentifier: rows[0].ownerProcessIdentifier, origin: .external)
        let presenter = PanelPresenter(
            surface: FakeSurface(),
            store: WindowListStore(gather: { passFinding([rows[1]]) }, writeLine: { _ in }),
            writeLine: { _ in },
            tracker: tracker
        )
        let fresh = await presenter.freshList(carrying: [])
        #expect(fresh?.windows.map(\.id) == [rows[1].id])
        #expect(tracker.newestSource == .external)
        #expect(tracker.arranged([rows[1], rows[0]]).map(\.id) == [rows[0].id, rows[1].id])
    }
}
