import ApplicationServices
import PrivateAPIs

///
/// Holds the mirror of the list on screen: what was shown is what a target
/// is resolved off, and the mirror is rewound when sending fails. The filter
/// and the way out keep their own copies beside this one — the same shape
/// they already keep between each other — and all three move through the one
/// entry that swaps the rows on screen.
@MainActor
final class PanelWindowOperations {
    private let selection: PanelSelection
    private let surface: any SwitcherSurface
    private let replaceList: @MainActor ([WindowItem]) -> Void
    private let refresh: @MainActor () async -> [WindowItem]
    private let closer: any WindowClosing
    private let quitter: any ApplicationQuitting
    private let hider: any ApplicationHiding
    private let ownProcessIdentifier: pid_t
    private let writeLine: @MainActor (String) -> Void
    private let closeAfterEmptied: @MainActor () -> Void
    private let closeForInterruption: @MainActor (WindowOperation, String, String) -> Void
    private var presented: [WindowItem] = []

    init(
        selection: PanelSelection,
        surface: any SwitcherSurface,
        replaceList: @escaping @MainActor ([WindowItem]) -> Void,
        refresh: @escaping @MainActor () async -> [WindowItem],
        closer: any WindowClosing,
        quitter: any ApplicationQuitting,
        hider: any ApplicationHiding,
        ownProcessIdentifier: pid_t,
        writeLine: @escaping @MainActor (String) -> Void,
        closeAfterEmptied: @escaping @MainActor () -> Void,
        closeForInterruption: @escaping @MainActor (WindowOperation, String, String) -> Void
    ) {
        self.selection = selection
        self.surface = surface
        self.replaceList = replaceList
        self.refresh = refresh
        self.closer = closer
        self.quitter = quitter
        self.hider = hider
        self.ownProcessIdentifier = ownProcessIdentifier
        self.writeLine = writeLine
        self.closeAfterEmptied = closeAfterEmptied
        self.closeForInterruption = closeForInterruption
    }

    /// Remembers what the appearance shows. Operations resolve off this,
    /// so a row gone from a fresher list is still a row that was shown.
    func begin(windows: [WindowItem]) {
        presented = windows
    }

    /// Gives the mirror up with the panel.
    func end() {
        presented = []
    }

    /// Sends one operation at the named row.
    func operate(_ operation: WindowOperation, naming id: WindowItem.Identifier?) async {
        switch operation {
        case .closeWindow:
            await close(naming: id)
        case .quitApplication:
            await quit(naming: id)
        case .hideApplication:
            await hide(naming: id)
        case .minimizeWindow:
            // Its story lands next. Until then the press is swallowed
            // without a trace.
            break
        }
    }

    /// The named row, unless it is out of scope — the process's own row is
    /// never a target, and neither is asking after what is already parked.
    /// Out of scope is not a failure: nothing happens, and no line says
    /// anything.
    private func resolve(
        _ id: WindowItem.Identifier?,
        for operation: WindowOperation
    ) -> (index: Int, row: WindowItem)? {
        guard let id, let index = presented.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let row = presented[index]
        guard row.ownerProcessIdentifier != ownProcessIdentifier else {
            return nil
        }
        if row.isParked, operation == .hideApplication || operation == .minimizeWindow {
            return nil
        }
        return (index, row)
    }

    private func close(naming id: WindowItem.Identifier?) async {
        guard let (index, row) = resolve(id, for: .closeWindow) else {
            return
        }
        let target = ActivationTarget(
            id: row.id,
            ownerProcessIdentifier: row.ownerProcessIdentifier,
            appName: row.appName,
            displayTitle: row.displayTitle
        )
        var optimistically = presented
        optimistically.remove(at: index)
        await sendAndReconcile(
            Reconciliation(
                operation: .closeWindow,
                row: row,
                index: index,
                optimistic: optimistically,
                send: { [closer] in closer.closeWindow(target) },
                isDone: { fresh in !fresh.contains(where: { $0.id == row.id }) },
                closesWhenEmpty: false
            )
        )
    }

    private func quit(naming id: WindowItem.Identifier?) async {
        guard let (index, row) = resolve(id, for: .quitApplication) else {
            return
        }
        let pid = row.ownerProcessIdentifier
        let optimistic = presented.filter { $0.ownerProcessIdentifier != pid }
        await sendAndReconcile(
            Reconciliation(
                operation: .quitApplication,
                row: row,
                index: index,
                optimistic: optimistic,
                send: { [quitter] in quitter.quitApplication(processIdentifier: pid) },
                isDone: { fresh in !fresh.contains(where: { $0.ownerProcessIdentifier == pid }) },
                closesWhenEmpty: true
            )
        )
    }

    private func hide(naming id: WindowItem.Identifier?) async {
        guard let (index, row) = resolve(id, for: .hideApplication) else {
            return
        }
        let pid = row.ownerProcessIdentifier
        let optimistic = presented.map { item in
            item.ownerProcessIdentifier == pid ? item.settingHidden(true) : item
        }
        await sendAndReconcile(
            Reconciliation(
                operation: .hideApplication,
                row: row,
                index: index,
                optimistic: optimistic,
                send: { [hider] in hider.hideApplication(processIdentifier: pid) },
                isDone: { fresh in
                    !fresh.contains(where: { $0.ownerProcessIdentifier == pid && !$0.isHidden })
                },
                closesWhenEmpty: false
            )
        )
    }

    /// One operation with everything reconciling it needs. A value rather
    /// than seven parameters, which is where the linter draws its line.
    private struct Reconciliation {
        let operation: WindowOperation
        let row: WindowItem
        let index: Int
        let optimistic: [WindowItem]
        let send: () -> ActivationFailure?
        let isDone: ([WindowItem]) -> Bool
        let closesWhenEmpty: Bool
    }

    /// Moves the look first, so the keystroke is answered at once, then
    /// waits out the reconciling passes for what the look got wrong. At
    /// most two passes: a slow but working application still answers by
    /// the second one, and only a row outliving both counts as interrupted.
    /// A failure winds the look back instead of waiting: nothing was sent.
    private func sendAndReconcile(_ reconciliation: Reconciliation) async {
        let snapshot = presented
        presented = reconciliation.optimistic
        replaceList(reconciliation.optimistic)
        moveChoice(from: reconciliation.index, in: reconciliation.optimistic)
        if let failure = reconciliation.send() {
            rewind(
                to: snapshot,
                selecting: reconciliation.row.id,
                operation: reconciliation.operation,
                row: reconciliation.row,
                failure: failure
            )
            return
        }
        for _ in 0 ..< 2 {
            let fresh = await refresh()
            if reconciliation.isDone(fresh) {
                presented = fresh
                replaceList(fresh)
                moveChoice(from: reconciliation.index, in: fresh)
                writeLine(
                    "window operation (\(reconciliation.operation.logName) "
                        + "\(reconciliation.row.appName)/\(reconciliation.row.displayTitle))"
                )
                if reconciliation.closesWhenEmpty, fresh.isEmpty {
                    closeAfterEmptied()
                }
                return
            }
        }
        closeForInterruption(
            reconciliation.operation,
            reconciliation.row.appName,
            reconciliation.row.displayTitle
        )
    }

    /// Winds the optimistic look back: the list and the choice are what
    /// they were, and one line says why.
    private func rewind(
        to snapshot: [WindowItem],
        selecting id: WindowItem.Identifier,
        operation: WindowOperation,
        row: WindowItem,
        failure: ActivationFailure
    ) {
        presented = snapshot
        replaceList(snapshot)
        selection.retarget(to: snapshot.map(\.id), selecting: id)
        surface.showSelection(id)
        writeLine(
            "window operation failed (\(operation.logName) "
                + "\(row.appName)/\(row.displayTitle): \(failure.logDescription))"
        )
    }

    /// The row now standing where the operated one stood, or the new last
    /// row when the operated one was last.
    private func moveChoice(from index: Int, in windows: [WindowItem]) {
        let ids = windows.map(\.id)
        let chosen: WindowItem.Identifier? = index < ids.count ? ids[index] : ids.last
        selection.retarget(to: ids, selecting: chosen)
        surface.showSelection(chosen)
    }
}
