/// The reconciling half of the window operations.
///
/// Split from the operations, which decide what each one sends and what
/// counts as done. Moving the look, waiting out the passes and winding the
/// look back are one question shared by every operation, and it grows
/// beside them rather than inside a type already close to the length the
/// linter allows.
extension PanelWindowOperations {
    /// One operation with everything reconciling it needs. A value rather
    /// than a parameter apiece, which is past where the linter draws its
    /// line.
    struct Reconciliation {
        let operation: WindowOperation
        let row: WindowItem
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
    ///
    /// Every swap moves the choice to the row now standing where the
    /// operated one stood among the rows shown before it, or to the new
    /// last shown row when it stood last. The filter does the counting,
    /// because only it knows which rows a query leaves on screen.
    func sendAndReconcile(_ reconciliation: Reconciliation) async {
        let snapshot = presented
        let anchor = ChoiceAnchor(id: reconciliation.row.id, stoodIn: snapshot)
        presented = reconciliation.optimistic
        replaceList(reconciliation.optimistic, anchor)
        if let failure = reconciliation.send() {
            rewind(
                to: snapshot,
                anchor: anchor,
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
                replaceList(fresh, anchor)
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
    /// they were, and one line says why. The anchor stands in the list it
    /// is wound back to, so the choice lands on the operated row again.
    private func rewind(
        to snapshot: [WindowItem],
        anchor: ChoiceAnchor,
        operation: WindowOperation,
        row: WindowItem,
        failure: ActivationFailure
    ) {
        presented = snapshot
        replaceList(snapshot, anchor)
        surface.showNotice("Couldn't \(operation.logName) \(row.displayTitle)")
        writeLine(
            "window operation failed (\(operation.logName) "
                + "\(row.appName)/\(row.displayTitle): \(failure.logDescription))"
        )
    }
}
