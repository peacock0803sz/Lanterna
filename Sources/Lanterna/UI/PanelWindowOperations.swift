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
    /// Reached beside the operations, by the reconciling half.
    let surface: any SwitcherSurface
    let replaceList: @MainActor ([WindowItem], ChoiceAnchor) -> Void
    let refresh: @MainActor () async -> [WindowItem]
    private let closer: any WindowClosing
    private let quitter: any ApplicationQuitting
    private let hider: any ApplicationHiding
    private let minimizer: any WindowMinimizing
    private let ownProcessIdentifier: pid_t
    /// Reached beside the operations, by the reconciling half.
    let writeLine: @MainActor (String) -> Void
    let closeAfterEmptied: @MainActor () -> Void
    let closeForInterruption: @MainActor (WindowOperation, String, String) -> Void
    /// Reached beside the operations, by the reconciling half.
    var presented: [WindowItem] = []

    init(
        surface: any SwitcherSurface,
        replaceList: @escaping @MainActor ([WindowItem], ChoiceAnchor) -> Void,
        refresh: @escaping @MainActor () async -> [WindowItem],
        closer: any WindowClosing,
        quitter: any ApplicationQuitting,
        hider: any ApplicationHiding,
        minimizer: any WindowMinimizing,
        ownProcessIdentifier: pid_t,
        writeLine: @escaping @MainActor (String) -> Void,
        closeAfterEmptied: @escaping @MainActor () -> Void,
        closeForInterruption: @escaping @MainActor (WindowOperation, String, String) -> Void
    ) {
        self.surface = surface
        self.replaceList = replaceList
        self.refresh = refresh
        self.closer = closer
        self.quitter = quitter
        self.hider = hider
        self.minimizer = minimizer
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
            await minimize(naming: id)
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
                optimistic: optimistically,
                send: { [closer] in closer.closeWindow(target) },
                isDone: { fresh in !fresh.contains(where: { $0.id == row.id }) },
                closesWhenEmpty: false
            )
        )
    }

    private func quit(naming id: WindowItem.Identifier?) async {
        guard let (_, row) = resolve(id, for: .quitApplication) else {
            return
        }
        let pid = row.ownerProcessIdentifier
        let optimistic = presented.filter { $0.ownerProcessIdentifier != pid }
        await sendAndReconcile(
            Reconciliation(
                operation: .quitApplication,
                row: row,
                optimistic: optimistic,
                send: { [quitter] in quitter.quitApplication(processIdentifier: pid) },
                isDone: { fresh in !fresh.contains(where: { $0.ownerProcessIdentifier == pid }) },
                closesWhenEmpty: true
            )
        )
    }

    private func hide(naming id: WindowItem.Identifier?) async {
        guard let (_, row) = resolve(id, for: .hideApplication) else {
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
                optimistic: optimistic,
                send: { [hider] in hider.hideApplication(processIdentifier: pid) },
                isDone: { fresh in
                    !fresh.contains(where: { $0.ownerProcessIdentifier == pid && !$0.isHidden })
                },
                closesWhenEmpty: false
            )
        )
    }

    private func minimize(naming id: WindowItem.Identifier?) async {
        guard let (_, row) = resolve(id, for: .minimizeWindow) else {
            return
        }
        let target = ActivationTarget(
            id: row.id,
            ownerProcessIdentifier: row.ownerProcessIdentifier,
            appName: row.appName,
            displayTitle: row.displayTitle
        )
        let optimistic = presented.map { $0.id == row.id ? $0.settingMinimized(true) : $0 }
        await sendAndReconcile(
            Reconciliation(
                operation: .minimizeWindow,
                row: row,
                optimistic: optimistic,
                send: { [minimizer] in minimizer.minimizeWindow(target) },
                isDone: { fresh in
                    fresh.first(where: { $0.id == row.id })?.isMinimized != false
                },
                closesWhenEmpty: false
            )
        )
    }
}
