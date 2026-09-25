import AppKit
@testable import Lanterna
import Testing

/// Rows with distinct names, so which rows match is decided by the test.
@MainActor
private func filterListRow(appName: String, windowTitle: String, windowID: CGWindowID) -> WindowItem {
    WindowItem(
        id: WindowItem.Identifier(windowID: windowID),
        ownerProcessIdentifier: 0,
        appName: appName,
        bundleIdentifier: nil,
        windowTitle: windowTitle,
        kind: .standard,
        isMinimized: false,
        icon: NSImage(size: NSSize(width: 1, height: 1))
    )
}

/// The narrowing seen from outside the presenter.
///
/// What the arithmetic does with identities is settled in `FilterStateTests`,
/// which needs no panel at all. What is settled here is everything that
/// arithmetic cannot reach: that typing narrows the rows on screen, that the
/// choice follows onto the narrowed list, that the exits resolve off the
/// narrowed snapshot, and that the panel is told through the entry that
/// leaves its size and position alone.
@MainActor
struct PanelFilterTests {
    private var rows: [WindowItem] {
        [
            filterListRow(appName: "Safari", windowTitle: "Update available", windowID: 1),
            filterListRow(appName: "Safari", windowTitle: "Downloads folder", windowID: 2),
            filterListRow(appName: "Finder", windowTitle: "Applications", windowID: 3),
        ]
    }

    /// Everything one narrowing drives, so each case reads off one value.
    private struct Harness {
        let filter: PanelFilter
        let surface: FakeSurface
        let log: DiagnosticsLog
        let selection: PanelSelection
        let wayOut: PanelExit
        let rows: [WindowItem]
    }

    private func makeFilter() -> Harness {
        let surface = FakeSurface()
        surface.isPresented = true
        let log = DiagnosticsLog()
        let selection = PanelSelection(surface: surface)
        let wayOut = PanelExit(
            surface: surface,
            now: { ContinuousClock.now },
            writeLine: log.write,
            switcher: FakeWindowSwitcher(),
            recordCommit: { _, _ in },
            noteSwitchReturned: {},
            onPanelGone: {}
        )
        let filter = PanelFilter(selection: selection, surface: surface, wayOut: wayOut)
        selection.beginSecond(rows.map(\.id))
        wayOut.nowShowing(rows, startedAt: ContinuousClock.now)
        filter.begin(fullWindows: rows)
        return Harness(
            filter: filter,
            surface: surface,
            log: log,
            selection: selection,
            wayOut: wayOut,
            rows: rows
        )
    }

    /// Typing narrows the rows on screen one keystroke at a time, keeping
    /// the choice while it still matches.
    @Test func typingNarrowsTheRowsProgressively() {
        let made = makeFilter()
        made.filter.append("s")
        #expect(made.surface.updatedLists.last?.map(\.id) == made.rows.map(\.id))
        made.filter.append("a")
        #expect(
            made.surface.updatedLists.last?.map(\.id) == [made.rows[0].id, made.rows[1].id]
        )
        #expect(made.selection.chosenID == made.rows[1].id)
    }

    /// Losing the chosen row moves to the first match; shortening back onto
    /// the remembered row restores it.
    @Test func losingAndShorteningMovesAndRestores() {
        let made = makeFilter()
        made.filter.append("update")
        #expect(made.surface.updatedLists.last?.map(\.id) == [made.rows[0].id])
        #expect(made.selection.chosenID == made.rows[0].id)
        for _ in 0 ..< 6 {
            made.filter.removeLast()
        }
        #expect(made.surface.updatedLists.last?.map(\.id) == made.rows.map(\.id))
        #expect(made.selection.chosenID == made.rows[1].id)
    }

    /// Narrowing further after moving with the arrows keeps the arrowed row;
    /// the memory does not pull the choice back.
    @Test func narrowingAfterMovingKeepsTheArrowedRow() {
        let made = makeFilter()
        made.filter.append("update")
        for _ in 0 ..< 6 {
            made.filter.removeLast()
        }
        made.selection.moveToNext()
        #expect(made.selection.chosenID == made.rows[2].id)
        made.filter.append("fin")
        #expect(made.selection.chosenID == made.rows[2].id)
    }

    /// Passing through an empty match remembers the row that vanished into
    /// it; clearing back to the whole list restores that row.
    @Test func passingThroughAnEmptyMatchKeepsTheMemory() {
        let made = makeFilter()
        made.filter.append("update")
        made.filter.append("x")
        #expect(made.surface.updatedLists.last?.isEmpty == true)
        #expect(made.selection.chosenID == nil)
        made.filter.removeLast()
        #expect(made.selection.chosenID == made.rows[0].id)
        for _ in 0 ..< 6 {
            made.filter.removeLast()
        }
        #expect(made.selection.chosenID == made.rows[0].id)
    }

    /// An empty match chooses nothing.
    @Test func anEmptyMatchChoosesNothing() {
        let made = makeFilter()
        made.filter.append("zzz")
        #expect(made.surface.updatedLists.last?.isEmpty == true)
        #expect(made.selection.chosenID == nil)
    }

    /// Moving wraps inside the narrowed list, never leaving it.
    @Test func movingWrapsInsideTheNarrowedList() {
        let made = makeFilter()
        made.filter.append("sa")
        made.selection.moveToNext()
        #expect(made.selection.chosenID == made.rows[0].id)
        made.selection.moveToNext()
        #expect(made.selection.chosenID == made.rows[1].id)
    }

    /// A commit names a row of the narrowed snapshot, not of the whole list.
    @Test func aCommitNamesARowOfTheNarrowedSnapshot() {
        let made = makeFilter()
        made.filter.append("down")
        made.wayOut.commit(
            by: .returnKey,
            naming: made.selection.chosenID,
            since: ContinuousClock.now
        )
        #expect(made.log.lines.contains { $0.contains("Downloads folder") })
        #expect(!made.log.lines.contains { $0.contains("Update available") })
    }
}
