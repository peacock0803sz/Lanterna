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
    private let ownProcessIdentifier: pid_t
    private let writeLine: @MainActor (String) -> Void
    private let closeForInterruption: @MainActor (WindowOperation, String, String) -> Void
    private var presented: [WindowItem] = []

    init(
        selection: PanelSelection,
        surface: any SwitcherSurface,
        replaceList: @escaping @MainActor ([WindowItem]) -> Void,
        refresh: @escaping @MainActor () async -> [WindowItem],
        closer: any WindowClosing,
        ownProcessIdentifier: pid_t,
        writeLine: @escaping @MainActor (String) -> Void,
        closeForInterruption: @escaping @MainActor (WindowOperation, String, String) -> Void
    ) {
        self.selection = selection
        self.surface = surface
        self.replaceList = replaceList
        self.refresh = refresh
        self.closer = closer
        self.ownProcessIdentifier = ownProcessIdentifier
        self.writeLine = writeLine
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
        case .quitApplication, .hideApplication, .minimizeWindow:
            // Their stories land next. Until then the press is swallowed
            // without a trace.
            break
        }
    }

    private func close(naming id: WindowItem.Identifier?) async {
        guard let id, let index = presented.firstIndex(where: { $0.id == id }) else {
            return
        }
        let row = presented[index]
        // Out of scope is not a failure: nothing happens, and no line
        // says anything.
        guard row.ownerProcessIdentifier != ownProcessIdentifier else {
            return
        }
        let snapshot = presented
        // Move the look first, so the keystroke is answered at once; the
        // reconciling pass below corrects whatever the look got wrong.
        var optimistically = presented
        optimistically.remove(at: index)
        presented = optimistically
        replaceList(optimistically)
        moveChoice(from: index, in: optimistically)
        let target = ActivationTarget(
            id: row.id,
            ownerProcessIdentifier: row.ownerProcessIdentifier,
            appName: row.appName,
            displayTitle: row.displayTitle
        )
        if let failure = closer.closeWindow(target) {
            presented = snapshot
            replaceList(snapshot)
            selection.retarget(to: snapshot.map(\.id), selecting: id)
            surface.showSelection(id)
            writeLine(
                "window operation failed (close \(row.appName)/\(row.displayTitle): \(failure.logDescription))"
            )
            return
        }
        // At most two passes: a slow but working application still lists
        // the row on the first one, and only a row outliving both counts
        // as interrupted.
        for _ in 0 ..< 2 {
            let fresh = await refresh()
            if !fresh.contains(where: { $0.id == id }) {
                presented = fresh
                replaceList(fresh)
                moveChoice(from: index, in: fresh)
                writeLine("window operation (close \(row.appName)/\(row.displayTitle))")
                return
            }
        }
        closeForInterruption(.closeWindow, row.appName, row.displayTitle)
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
