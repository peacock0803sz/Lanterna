import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// Rows with distinct names, so which rows survive is decided by the test.
@MainActor
private func operationRow(
    appName: String,
    windowTitle: String,
    windowID: CGWindowID,
    pid: pid_t = 123
) -> WindowItem {
    WindowItem(
        id: WindowItem.Identifier(windowID: windowID),
        ownerProcessIdentifier: pid,
        appName: appName,
        bundleIdentifier: nil,
        windowTitle: windowTitle,
        kind: .standard,
        isMinimized: false,
        icon: NSImage(size: NSSize(width: 1, height: 1))
    )
}

/// A scripted closer: answers what sending comes to.
private struct FakeCloser: WindowClosing, Sendable {
    let close: @Sendable (ActivationTarget) -> ActivationFailure?
    func closeWindow(_ target: ActivationTarget) -> ActivationFailure? {
        close(target)
    }
}

/// A scripted quitter and hider.
private struct FakeQuitter: ApplicationQuitting, Sendable {
    let quit: @Sendable (pid_t) -> ActivationFailure?
    func quitApplication(processIdentifier pid: pid_t) -> ActivationFailure? {
        quit(pid)
    }
}

private struct FakeHider: ApplicationHiding, Sendable {
    let hide: @Sendable (pid_t) -> ActivationFailure?
    func hideApplication(processIdentifier pid: pid_t) -> ActivationFailure? {
        hide(pid)
    }
}

/// A scripted minimizer.
private struct FakeMinimizer: WindowMinimizing, Sendable {
    let minimize: @Sendable (ActivationTarget) -> ActivationFailure?
    func minimizeWindow(_ target: ActivationTarget) -> ActivationFailure? {
        minimize(target)
    }
}

/// A box so the harness counts refreshes, interruptions and empty closes.
private final class OperationCounts {
    var refreshes = 0
    var interruptions = 0
    var emptied = 0
}

/// Everything one operation drives, so each case reads off one value.
@MainActor
private struct OperationHarness {
    let operations: PanelWindowOperations
    let surface: FakeSurface
    let selection: PanelSelection
    let filter: PanelFilter
    let wayOut: PanelExit
    let switcher: FakeWindowSwitcher
    let log: DiagnosticsLog
    let counts: OperationCounts
    let rows: [WindowItem]
}

/// The collaborators one appearance needs, without the operations.
@MainActor
private struct FilterStack {
    let selection: PanelSelection
    let wayOut: PanelExit
    let filter: PanelFilter
}

@MainActor
private func makeStack(surface: FakeSurface, log: DiagnosticsLog, switcher: FakeWindowSwitcher) -> FilterStack {
    let selection = PanelSelection(surface: surface)
    let wayOut = PanelExit(
        surface: surface,
        now: { ContinuousClock.now },
        writeLine: log.write,
        switcher: switcher,
        recordCommit: { _, _ in },
        noteSwitchReturned: {},
        onPanelGone: {}
    )
    let filter = PanelFilter(selection: selection, surface: surface)
    return FilterStack(selection: selection, wayOut: wayOut, filter: filter)
}

/// Starts one appearance over the rows on every keeper of them.
@MainActor
private func beginAppearance(
    selection: PanelSelection,
    wayOut: PanelExit,
    filter: PanelFilter,
    operations: PanelWindowOperations,
    rows: [WindowItem]
) {
    selection.beginSecond(rows.map(\.id))
    wayOut.nowShowing(rows, startedAt: ContinuousClock.now)
    filter.begin(fullWindows: rows)
    operations.begin(windows: rows)
}

@MainActor
private func makeOperations(
    rows: [WindowItem],
    refreshed: [WindowItem]? = nil,
    close: @escaping @Sendable (ActivationTarget) -> ActivationFailure? = { _ in nil },
    quit: @escaping @Sendable (pid_t) -> ActivationFailure? = { _ in nil },
    hide: @escaping @Sendable (pid_t) -> ActivationFailure? = { _ in nil },
    minimize: @escaping @Sendable (ActivationTarget) -> ActivationFailure? = { _ in nil },
    ownProcessIdentifier: pid_t = 999
) -> OperationHarness {
    let surface = FakeSurface()
    surface.isPresented = true
    let log = DiagnosticsLog()
    let switcher = FakeWindowSwitcher()
    let stack = makeStack(surface: surface, log: log, switcher: switcher)
    let selection = stack.selection
    let wayOut = stack.wayOut
    let filter = stack.filter
    let counts = OperationCounts()
    let fresh = refreshed ?? rows
    let operations = PanelWindowOperations(
        selection: selection,
        surface: surface,
        replaceList: { [weak filter, weak wayOut] renewed in
            filter?.replace(fullWindows: renewed)
            wayOut?.replacePresented(renewed)
        },
        refresh: {
            counts.refreshes += 1
            return fresh
        },
        closer: FakeCloser(close: close),
        quitter: FakeQuitter(quit: quit),
        hider: FakeHider(hide: hide),
        minimizer: FakeMinimizer(minimize: minimize),
        ownProcessIdentifier: ownProcessIdentifier,
        writeLine: log.write,
        closeAfterEmptied: { counts.emptied += 1 },
        closeForInterruption: { [weak wayOut] operation, appName, displayTitle in
            counts.interruptions += 1
            wayOut?.closeAfterInterruptedOperation(
                operation: operation,
                appName: appName,
                displayTitle: displayTitle
            )
        }
    )
    beginAppearance(selection: selection, wayOut: wayOut, filter: filter, operations: operations, rows: rows)
    return OperationHarness(
        operations: operations,
        surface: surface,
        selection: selection,
        filter: filter,
        wayOut: wayOut,
        switcher: switcher,
        log: log,
        counts: counts,
        rows: rows
    )
}

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
    /// closes on it, writing one line that says the row is still there.
    @Test func aRemainingRowAfterSendingClosesThePanel() async {
        let made = makeOperations(rows: rows, refreshed: rows)
        await made.operations.operate(.closeWindow, naming: rows[0].id)
        #expect(made.counts.interruptions == 1)
        #expect(made.log.lines.contains { $0.contains("is still open") })
    }

    /// The process's own row is out of scope: nothing happens, and no line
    /// says anything.
    @Test func theOwnRowIsLeftAlone() async {
        let own = operationRow(appName: "Lanterna", windowTitle: "Panel", windowID: 9, pid: 999)
        let made = makeOperations(rows: [own], refreshed: [own], ownProcessIdentifier: 999)
        await made.operations.operate(.closeWindow, naming: own.id)
        #expect(made.surface.updatedLists.isEmpty)
        #expect(made.log.lines.isEmpty)
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

    /// Hiding parks every row of the application below the separator.
    @Test func hidingParksTheWholeApplication() async {
        let parked = twoApps.map { $0.ownerProcessIdentifier == 123 ? $0.settingHidden(true) : $0 }
        let made = makeOperations(rows: twoApps, refreshed: parked)
        made.selection.retarget(to: twoApps.map(\.id), selecting: twoApps[0].id)
        await made.operations.operate(.hideApplication, naming: twoApps[0].id)
        let shown = made.surface.updatedLists.last ?? []
        #expect(shown.filter(\.isHidden).map(\.id) == [twoApps[0].id, twoApps[1].id])
        #expect(shown.filter { !$0.isHidden }.map(\.id) == [twoApps[2].id])
        #expect(made.selection.chosenID == twoApps[0].id)
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

    /// Minimizing parks the row below the separator.
    @Test func minimizingParksTheRow() async {
        let parked = [rows[0].settingMinimized(true), rows[1], rows[2]]
        let made = makeOperations(rows: rows, refreshed: parked)
        made.selection.retarget(to: rows.map(\.id), selecting: rows[0].id)
        await made.operations.operate(.minimizeWindow, naming: rows[0].id)
        let shown = made.surface.updatedLists.last ?? []
        #expect(shown.first?.isMinimized == true)
        #expect(made.selection.chosenID == rows[0].id)
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
