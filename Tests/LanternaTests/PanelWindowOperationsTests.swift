import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

@MainActor
struct PanelWindowOperationsTests {
    private var rows: [WindowItem] {
        [
            operationRow(appName: "Safari", windowTitle: "Tabs", windowID: 1),
            operationRow(appName: "Safari", windowTitle: "Downloads", windowID: 2),
            operationRow(appName: "Finder", windowTitle: "AirDrop", windowID: 3),
        ]
    }

    /// Closing removes the row, keeps the panel up, and moves the choice to
    /// the row now standing where the closed one stood.
    @Test func closingRemovesTheRowAndMovesTheChoice() async {
        let made = makeOperations(rows: rows, refreshed: [rows[1], rows[2]])
        made.selection.retarget(to: rows.map(\.id), selecting: rows[0].id)
        await made.operations.operate(.closeWindow, naming: rows[0].id)
        #expect(made.surface.updatedLists.last?.map(\.id) == [rows[1].id, rows[2].id])
        #expect(made.selection.chosenID == rows[1].id)
        #expect(made.log.lines.contains { $0.contains("window operation (close Safari/Tabs)") })
    }

    /// Closing the last row moves the choice to the new last row.
    @Test func closingTheLastRowMovesTheChoiceBack() async {
        let made = makeOperations(rows: rows, refreshed: [rows[0], rows[1]])
        await made.operations.operate(.closeWindow, naming: rows[2].id)
        #expect(made.selection.chosenID == rows[1].id)
    }

    /// A failure winds the optimistic update back: the list and the choice
    /// are what they were, the refresh never runs, and one line says why.
    @Test func aFailureWindsBackAndKeepsTheChoice() async {
        let made = makeOperations(
            rows: rows,
            refreshed: [],
            close: { _ in .windowGone },
            ownProcessIdentifier: 999
        )
        made.selection.retarget(to: rows.map(\.id), selecting: rows[0].id)
        await made.operations.operate(.closeWindow, naming: rows[0].id)
        #expect(made.counts.refreshes == 0)
        #expect(made.surface.updatedLists.last?.map(\.id) == rows.map(\.id))
        #expect(made.selection.chosenID == rows[0].id)
        #expect(
            made.log.lines.contains {
                $0.contains("window operation failed (close Safari/Tabs: window gone)")
            }
        )
        #expect(made.surface.notices.last?.contains("Couldn't close") == true)
    }

    /// A sent request the refresh still lists is an interruption: the panel
    /// closes on it, writing one line that says the change was not confirmed.
    @Test func aRemainingRowAfterSendingClosesThePanel() async {
        let made = makeOperations(rows: rows, refreshed: rows)
        await made.operations.operate(.closeWindow, naming: rows[0].id)
        #expect(made.counts.interruptions == 1)
        #expect(made.log.lines.contains { $0 == "closed the panel (close not confirmed: Safari/Tabs)" })
    }

    /// A pass that could not read the operated row's application decides
    /// nothing: its missing row is not a closed window, so no success is
    /// written and a row undecided through every pass reads as an
    /// interruption.
    @Test func aSkippedApplicationIsNotReadAsDone() async {
        let made = makeOperations(rows: rows, refreshed: [rows[2]], skipped: [123])
        await made.operations.operate(.closeWindow, naming: rows[0].id)
        #expect(made.counts.refreshes == 2)
        #expect(!made.log.lines.contains { $0.contains("window operation (close") })
        #expect(made.counts.interruptions == 1)
    }

    /// No pass having finished is undecided rather than an empty list.
    @Test func noListIsNotReadAsDone() async {
        let made = makeOperations(rows: rows, refreshed: [], skipped: nil)
        await made.operations.operate(.minimizeWindow, naming: rows[0].id)
        #expect(!made.log.lines.contains { $0.contains("window operation (minimize") })
        #expect(made.counts.interruptions == 1)
    }

    /// The next keystroke clears the failure note.
    @Test func theNextKeystrokeClearsTheNotice() async {
        let made = makeOperations(
            rows: rows,
            refreshed: [],
            close: { _ in .windowGone },
            ownProcessIdentifier: 999
        )
        made.selection.retarget(to: rows.map(\.id), selecting: rows[0].id)
        await made.operations.operate(.closeWindow, naming: rows[0].id)
        #expect(made.surface.notices.isEmpty == false)
        let commands = PanelKeyCommands(
            surface: made.surface,
            selection: made.selection,
            wayOut: made.wayOut,
            now: { ContinuousClock.now }
        )
        commands.beginFiltering(fullWindows: rows, filtering: false)
        let down = PanelKeystroke(
            keyCode: UInt16(kVK_DownArrow),
            modifiers: [],
            isARepeat: false,
            characters: ""
        )
        #expect(commands.handle(down) == .absorbed)
        #expect(made.surface.clearedNotices == 1)
        #expect(made.surface.currentNotice == nil)
    }

    /// Swapping the list clears the failure note.
    @Test func swappingTheListClearsTheNotice() async {
        let made = makeOperations(
            rows: rows,
            refreshed: [],
            close: { _ in .windowGone },
            ownProcessIdentifier: 999
        )
        made.selection.retarget(to: rows.map(\.id), selecting: rows[0].id)
        await made.operations.operate(.closeWindow, naming: rows[0].id)
        #expect(made.surface.notices.isEmpty == false)
        made.filter.replace(fullWindows: rows)
        #expect(made.surface.currentNotice == nil)
    }

    /// Operating while narrowed keeps the query over the reconciled list.
    @Test func operatingWhileNarrowedKeepsTheQuery() async {
        let made = makeOperations(rows: rows, refreshed: [rows[1], rows[2]])
        made.filter.activate()
        made.filter.append("a")
        made.selection.retarget(to: rows.map(\.id), selecting: rows[0].id)
        await made.operations.operate(.closeWindow, naming: rows[0].id)
        #expect(made.surface.updatedQueries.last == "a")
        #expect(made.selection.chosenID == rows[1].id)
    }

    /// Operating while a query hides rows moves the choice among the shown
    /// rows only: the row after the operated one on screen, never a row the
    /// query hides. A walk with the arrows stays on the shown rows too.
    @Test func operatingWhileNarrowedChoosesOnlyShownRows() async {
        let mixed = [
            operationRow(appName: "Safari", windowTitle: "Tabs", windowID: 1),
            operationRow(appName: "Mail", windowTitle: "Inbox", windowID: 2),
            operationRow(appName: "Safari", windowTitle: "Downloads", windowID: 3),
            operationRow(appName: "Mail", windowTitle: "Drafts", windowID: 4),
            operationRow(appName: "Safari", windowTitle: "History", windowID: 5),
        ]
        let made = makeOperations(rows: mixed, refreshed: Array(mixed.dropFirst()))
        made.filter.activate()
        made.filter.append("safari")
        made.selection.retarget(to: [mixed[0].id, mixed[2].id, mixed[4].id], selecting: mixed[0].id)
        await made.operations.operate(.closeWindow, naming: mixed[0].id)
        #expect(made.surface.updatedLists.last?.map(\.id) == [mixed[2].id, mixed[4].id])
        #expect(made.selection.chosenID == mixed[2].id)
        made.selection.moveToNext()
        #expect(made.selection.chosenID == mixed[4].id)
    }

    /// Operating on a shown row in the middle counts its place among the
    /// shown rows: the next shown row takes the choice, not the row at the
    /// same place in the whole list.
    @Test func operatingOnAMiddleShownRowCountsAmongShownRows() async {
        let mixed = [
            operationRow(appName: "Safari", windowTitle: "Tabs", windowID: 1),
            operationRow(appName: "Mail", windowTitle: "Inbox", windowID: 2),
            operationRow(appName: "Safari", windowTitle: "Downloads", windowID: 3),
            operationRow(appName: "Mail", windowTitle: "Drafts", windowID: 4),
            operationRow(appName: "Safari", windowTitle: "History", windowID: 5),
            operationRow(appName: "Safari", windowTitle: "Bookmarks", windowID: 6),
        ]
        let made = makeOperations(rows: mixed, refreshed: [mixed[0], mixed[1], mixed[3], mixed[4], mixed[5]])
        made.filter.activate()
        made.filter.append("safari")
        made.selection.retarget(to: [mixed[0].id, mixed[2].id, mixed[4].id, mixed[5].id], selecting: mixed[2].id)
        await made.operations.operate(.closeWindow, naming: mixed[2].id)
        #expect(made.surface.updatedLists.last?.map(\.id) == [mixed[0].id, mixed[4].id, mixed[5].id])
        #expect(made.selection.chosenID == mixed[4].id)
    }

    /// A failure winds the choice back onto the operated row even when an
    /// earlier query remembered another row: winding back returns rows to
    /// the list, and the one returning is not a row the user asked for.
    @Test func aFailureWindsBackOntoTheOperatedRowOverARememberedOne() async {
        let rows = twoApps
        let made = makeOperations(rows: rows, refreshed: [], quit: { _ in .windowGone })
        made.filter.activate()
        made.selection.retarget(to: rows.map(\.id), selecting: rows[1].id)
        made.filter.append("t")
        made.filter.removeLast()
        #expect(made.selection.chosenID == rows[1].id)
        made.selection.moveToPrevious()
        await made.operations.operate(.quitApplication, naming: rows[0].id)
        #expect(made.surface.updatedLists.last?.map(\.id) == rows.map(\.id))
        #expect(made.selection.chosenID == rows[0].id)
    }

    /// Asking after what is already parked is not a failure: nothing
    /// happens, and no line says anything.
    @Test func minimizingAParkedRowDoesNothing() async {
        let parked = [rows[0].settingMinimized(true), rows[1], rows[2]]
        let made = makeOperations(rows: parked, refreshed: parked)
        await made.operations.operate(.minimizeWindow, naming: rows[0].id)
        #expect(made.surface.updatedLists.isEmpty)
        #expect(made.log.lines.isEmpty)
    }

    private var twoApps: [WindowItem] {
        [
            operationRow(appName: "Safari", windowTitle: "Tabs", windowID: 1, pid: 123),
            operationRow(appName: "Safari", windowTitle: "Downloads", windowID: 2, pid: 123),
            operationRow(appName: "Finder", windowTitle: "AirDrop", windowID: 3, pid: 124),
        ]
    }

    /// Quitting removes every row of the application, keeps the panel up,
    /// and moves the choice to the row now standing where the chosen one
    /// stood.
    @Test func quittingRemovesTheWholeApplication() async {
        let staying = [twoApps[2]]
        let made = makeOperations(rows: twoApps, refreshed: staying)
        made.selection.retarget(to: twoApps.map(\.id), selecting: twoApps[0].id)
        await made.operations.operate(.quitApplication, naming: twoApps[0].id)
        #expect(made.surface.updatedLists.last?.map(\.id) == [twoApps[2].id])
        #expect(made.selection.chosenID == twoApps[2].id)
        #expect(made.log.lines.contains { $0.contains("window operation (quit Safari/Tabs)") })
    }

    /// Hiding parks every row of the application below the separator, and
    /// the choice stays at the place the chosen row left: the row in use
    /// now standing there takes it.
    @Test func hidingParksTheWholeApplication() async {
        let parked = twoApps.map { $0.ownerProcessIdentifier == 123 ? $0.settingHidden(true) : $0 }
        let made = makeOperations(rows: twoApps, refreshed: parked)
        made.selection.retarget(to: twoApps.map(\.id), selecting: twoApps[0].id)
        await made.operations.operate(.hideApplication, naming: twoApps[0].id)
        let shown = made.surface.updatedLists.last ?? []
        #expect(shown.map(\.id) == [twoApps[2].id, twoApps[0].id, twoApps[1].id])
        #expect(shown.map(\.isHidden) == [false, true, true])
        #expect(made.selection.chosenID == twoApps[2].id)
        #expect(made.log.lines.contains { $0.contains("window operation (hide Safari/Tabs)") })
    }

    /// Quitting the last application closes the panel; anything else stays
    /// open over the empty list.
    @Test func quittingTheLastApplicationClosesThePanel() async {
        let alone = [twoApps[0]]
        let made = makeOperations(rows: alone, refreshed: [])
        await made.operations.operate(.quitApplication, naming: twoApps[0].id)
        #expect(made.counts.emptied == 1)
    }

    /// Minimizing parks the row below the separator, and the choice stays
    /// at the place the row left: the next row in use takes it.
    @Test func minimizingParksTheRow() async {
        let parked = [rows[1], rows[2], rows[0].settingMinimized(true)]
        let made = makeOperations(rows: rows, refreshed: parked)
        made.selection.retarget(to: rows.map(\.id), selecting: rows[0].id)
        await made.operations.operate(.minimizeWindow, naming: rows[0].id)
        let shown = made.surface.updatedLists.last ?? []
        #expect(shown.map(\.id) == [rows[1].id, rows[2].id, rows[0].id])
        #expect(shown.last?.isMinimized == true)
        #expect(made.selection.chosenID == rows[1].id)
        #expect(made.log.lines.contains { $0.contains("window operation (minimize Safari/Tabs)") })
    }

    /// A parked row commits through the swapped list: the exit names the
    /// row the panel last showed, so restoring takes the existing path.
    @Test func aParkedRowCommitsThroughTheSwappedList() async {
        let parked = twoApps.map { $0.ownerProcessIdentifier == 123 ? $0.settingHidden(true) : $0 }
        let made = makeOperations(rows: twoApps, refreshed: parked)
        await made.operations.operate(.hideApplication, naming: twoApps[0].id)
        made.wayOut.commit(
            by: .returnKey,
            naming: twoApps[0].id,
            since: ContinuousClock.now
        )
        #expect(made.switcher.targets.map(\.id) == [twoApps[0].id])
        #expect(made.log.lines.contains { $0.contains("Tabs") })
    }

    @Test func hidingEverythingKeepsThePanelOpen() async {
        let alone = [twoApps[0]]
        let made = makeOperations(rows: alone, refreshed: [])
        await made.operations.operate(.hideApplication, naming: twoApps[0].id)
        #expect(made.counts.emptied == 0)
        #expect(made.surface.updatedLists.last?.isEmpty == true)
    }
}
