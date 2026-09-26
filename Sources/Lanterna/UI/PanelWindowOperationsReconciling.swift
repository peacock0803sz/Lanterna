/// The reconciling half of the window operations.
///
/// Split from the operations, which decide what each one sends and what
/// counts as done. Moving the look, waiting out the passes and winding the
/// look back are one question shared by every operation, and it grows
/// beside them rather than inside a type already close to the length the
/// linter allows.
extension PanelWindowOperations {
    /// One operation with everything reconciling it needs. A value rather
    /// than seven parameters, which is where the linter draws its line.
    struct Reconciliation {
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
    func sendAndReconcile(_ reconciliation: Reconciliation) async {
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
        surface.showNotice("Couldn't \(operation.logName) \(row.displayTitle)")
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
