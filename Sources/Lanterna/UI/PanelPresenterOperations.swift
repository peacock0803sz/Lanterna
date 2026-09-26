/// The presenter's wiring for the way out and the window operations.
///
/// Split from the presenter, which decides when a panel goes up. Building
/// the way out and the operations, and handing each the closures that reach
/// back into the presenter, is wiring rather than deciding; carrying an
/// operation out is `PanelWindowOperations`' job. Kept beside the presenter
/// rather than inside a file already close to the length the linter allows.
extension PanelPresenter {
    /// Makes the way out, handing it what each exit needs. Built by a
    /// function rather than written out beside the property, because the
    /// way out and the command watch name each other and their types cannot
    /// both be worked out from expressions naming the other.
    func makeWayOut() -> PanelExit {
        PanelExit(
            surface: surface,
            now: now,
            writeLine: writeLine,
            keyStatusWatchInterval: keyStatusWatchInterval,
            switcher: switcher,
            recordCommit: { [weak self] id, pid in
                self?.tracker.record(id, ownerProcessIdentifier: pid, origin: .commit)
            },
            noteSwitchReturned: { [weak self] in self?.tracker.noteSwitchReturned() },
            onPanelGone: { [weak self] in
                self?.commandWatch.stop()
                self?.selection.end()
                self?.keyCommands.endFiltering()
                self?.operations.end()
            }
        )
    }

    /// Makes the carrier, wired to the commands, the way out and the list.
    /// Reached through the `lazy` property rather than directly, so no two
    /// `lazy` properties name each other.
    func makeOperations() -> PanelWindowOperations {
        PanelWindowOperations(
            surface: surface,
            replaceList: { [weak self] renewed, anchor in
                self?.replacePresentedList(renewed, choosingWhere: anchor)
            },
            refresh: { [weak self] previous in await self?.freshList(carrying: previous) },
            closer: LiveWindowCloser(),
            quitter: LiveApplicationQuitter(),
            hider: LiveApplicationHider(),
            minimizer: LiveWindowMinimizer(),
            ownProcessIdentifier: ownProcessIdentifier,
            writeLine: writeLine,
            closeAfterEmptied: { [weak self] in self?.wayOut.closeAfterEmptiedList(operation: .quitApplication) },
            closeForInterruption: { [weak self] operation, appName, displayTitle in
                self?.closeForInterruption(operation, appName: appName, displayTitle: displayTitle)
            }
        )
    }

    /// Sends one operation at the row chosen as the key was pressed. Taken
    /// in at once rather than when a task gets its turn, so the appearance
    /// it belongs to and the one-at-a-time rule are settled at the press.
    func startOperation(_ operation: WindowOperation, naming id: WindowItem.Identifier?) {
        operations.start(operation, naming: id)
    }

    /// Swaps the rows on screen for the reconciled list.
    func replacePresentedList(_ windows: [WindowItem], choosingWhere anchor: ChoiceAnchor) {
        keyCommands.replacePresentedList(windows, choosingWhere: anchor)
    }

    /// Takes the panel down for an interrupted operation.
    func closeForInterruption(
        _ operation: WindowOperation,
        appName: String,
        displayTitle: String
    ) {
        wayOut.closeAfterInterruptedOperation(
            operation: operation,
            appName: appName,
            displayTitle: displayTitle
        )
    }

    /// The freshest list in the order the appearance draws, waiting for the
    /// store's next completed pass. Sorted without sweeping: the appearance
    /// already swept against its own snapshot.
    ///
    /// Rows of applications the pass could not read are carried over from
    /// the list shown before it: absence from a list that never looked is
    /// not absence. Nothing when no pass has finished, which is undecided
    /// rather than empty.
    func freshList(carrying previous: [WindowItem]) async -> PanelWindowOperations.ReconcilingList? {
        await store.refreshEventually()
        guard let snapshot = store.snapshot else { return nil }
        let skipped = snapshot.skippedOwners
        let listed = Set(snapshot.items.map(\.id))
        let carried = previous.filter { skipped.contains($0.ownerProcessIdentifier) && !listed.contains($0.id) }
        return PanelWindowOperations.ReconcilingList(
            windows: tracker.arranged(snapshot.items + carried),
            skippedOwners: skipped
        )
    }
}
