import AppKit
@testable import Lanterna
import Testing

/// Rows with distinct names, so which rows survive is decided by the test.
@MainActor
func operationRow(
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
struct FakeCloser: WindowClosing, Sendable {
    let close: @Sendable (ActivationTarget) -> ActivationFailure?
    func closeWindow(_ target: ActivationTarget) -> ActivationFailure? {
        close(target)
    }
}

/// A scripted quitter and hider.
struct FakeQuitter: ApplicationQuitting, Sendable {
    let quit: @Sendable (pid_t) -> ActivationFailure?
    func quitApplication(processIdentifier pid: pid_t) -> ActivationFailure? {
        quit(pid)
    }
}

struct FakeHider: ApplicationHiding, Sendable {
    let hide: @Sendable (pid_t) -> ActivationFailure?
    func hideApplication(processIdentifier pid: pid_t) -> ActivationFailure? {
        hide(pid)
    }
}

/// A scripted minimizer.
struct FakeMinimizer: WindowMinimizing, Sendable {
    let minimize: @Sendable (ActivationTarget) -> ActivationFailure?
    func minimizeWindow(_ target: ActivationTarget) -> ActivationFailure? {
        minimize(target)
    }
}

/// A box so the harness counts refreshes, interruptions and empty closes.
final class OperationCounts {
    var refreshes = 0
    var interruptions = 0
    var emptied = 0
}

/// A refresh the test holds open, so the panel can be made to go — or a
/// later appearance come up — while an operation is genuinely waiting for
/// its list rather than whenever two tasks happen to interleave.
///
/// Holds one refresh at a time. A second one asked while the first is held
/// records an issue, which fails the case, and then answers an empty list
/// at once rather than waiting on a refresh nobody releases.
@MainActor
final class HeldRefresh {
    private(set) var askedCount = 0
    private var asked: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<[WindowItem], Never>?

    func refresh() async -> [WindowItem] {
        askedCount += 1
        asked?.resume()
        asked = nil
        guard release == nil else {
            Issue.record("a refresh was asked while another was held")
            return []
        }
        return await withCheckedContinuation { release = $0 }
    }

    /// Returns once the refresh has been asked for the given number of
    /// times in all, at once when it already has.
    func waitUntilAsked(count: Int = 1) async {
        while askedCount < count {
            await withCheckedContinuation { asked = $0 }
        }
    }

    func finish(with windows: [WindowItem]) {
        release?.resume(returning: windows)
        release = nil
    }
}

/// Everything one operation drives, so each case reads off one value.
@MainActor
struct OperationHarness {
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
func makeOperations(
    rows: [WindowItem],
    refreshed: [WindowItem]? = nil,
    held: HeldRefresh? = nil,
    skipped: Set<pid_t>? = [],
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
        surface: surface,
        replaceList: { [weak filter, weak wayOut] renewed, anchor in
            filter?.replace(fullWindows: renewed, choosingWhere: anchor)
            wayOut?.replacePresented(renewed)
        },
        // No skipped set stands for no pass having finished at all.
        refresh: { _ in
            counts.refreshes += 1
            let windows = await held?.refresh() ?? fresh
            return skipped.map { PanelWindowOperations.ReconcilingList(windows: windows, skippedOwners: $0) }
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
