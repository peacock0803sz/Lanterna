import Darwin

/// The reconciling half of the window operations.
///
/// Split from the operations, which decide what each one sends and what
/// counts as done. Moving the look, waiting out the passes and winding the
/// look back are one question shared by every operation, and it grows
/// beside them rather than inside a type already close to the length the
/// linter allows.
extension PanelWindowOperations {
    /// A list read for reconciling, and the applications its pass could not
    /// read. Their rows are missing because the look missed, not because
    /// the windows went, so a pass that skipped the operated row's
    /// application decides nothing about it.
    struct ReconcilingList {
        let windows: [WindowItem]
        let skippedOwners: Set<pid_t>
    }

    /// One operation with everything reconciling it needs. A value rather
    /// than a parameter list longer than the linter allows.
    struct Reconciliation {
        let operation: WindowOperation
        let row: WindowItem
        let optimistic: [WindowItem]
        let send: () -> ActivationFailure?
        let isDone: ([WindowItem]) -> Bool
        let closesWhenEmpty: Bool
    }

    /// Moves the look first, so the keystroke is answered at once, then
    /// waits out a bounded number of reconciling passes for what the look
    /// got wrong. A row that outlives them counts as interrupted. A pass
    /// that could not decide counts against the bound like one that found
    /// the row, so a row that stays undecided through every pass ends as an
    /// interruption too.
    /// A failure winds the look back instead of waiting. The sender said it
    /// could not act, though a time-out may come after the request went out
    /// and the application may still act on it.
    ///
    /// Every swap moves the choice to the row now standing where the
    /// operated one stood among the rows shown before it, or to the last
    /// shown row when fewer are shown now. The filter does the counting,
    /// because only it knows which rows a query leaves on screen.
    ///
    /// Every wait is a place the panel can go, or a later appearance come
    /// up, before this resumes. Each one is followed by asking whether the
    /// appearance is still the one this set out in; if not, nothing is
    /// touched — no list, no choice, no closing — and one line says the
    /// operation went unreconciled.
    func sendAndReconcile(_ reconciliation: Reconciliation) async {
        let generation = appearance
        let snapshot = presented
        let anchor = ChoiceAnchor(id: reconciliation.row.id, stoodIn: snapshot)
        // Hiding and minimizing mark rows parked where they stand, and the
        // panel draws parked rows below the separator, so the list moves
        // them there as the fresh list will have them.
        let optimistic = WindowItem.parkedLast(reconciliation.optimistic)
        presented = optimistic
        replaceList(optimistic, anchor)
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
            let fresh = await refresh(presented)
            guard appearance == generation else {
                writeLine(
                    "window operation left unreconciled (\(reconciliation.operation.logName) "
                        + "\(reconciliation.row.appName)/\(reconciliation.row.displayTitle); the panel went)"
                )
                return
            }
            // No list at all, or one whose pass skipped the operated row's
            // application, is undecided rather than done: the next pass
            // is asked instead.
            guard let fresh, !fresh.skippedOwners.contains(reconciliation.row.ownerProcessIdentifier) else {
                continue
            }
            if reconciliation.isDone(fresh.windows) {
                presented = fresh.windows
                replaceList(fresh.windows, anchor)
                writeLine(
                    "window operation (\(reconciliation.operation.logName) "
                        + "\(reconciliation.row.appName)/\(reconciliation.row.displayTitle))"
                )
                if reconciliation.closesWhenEmpty, fresh.windows.isEmpty {
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
