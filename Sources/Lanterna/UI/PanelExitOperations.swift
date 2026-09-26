/// The ways out that reconciling an operation needs.
///
/// Split from the exit, which decides when a panel comes down with what
/// line. Swapping the shown list and closing for an interruption are the
/// operations' questions, and they grow beside the operations rather than
/// inside a file already close to the length the linter allows.
extension PanelExit {
    /// Takes the panel down because quitting emptied the list. Only
    /// quitting closes over emptiness: every other operation stays open
    /// over it, so the tidying can go on.
    func closeAfterEmptiedList(operation: WindowOperation) {
        dismissPanel()
        writeLine("closed the panel (\(operation.logName) emptied the list)")
    }

    /// The wording for the disappearances that are the app tidying up after
    /// itself rather than the user deciding anything.
    func takeDown(because reason: String) {
        dismissPanel()
        writeLine("panel hidden (\(reason))")
    }

    /// Swaps the list an appearance is showing, after reconciling an
    /// operation against a fresher one. Commits keep naming rows of what
    /// the panel showed last, so the swap has to reach this list as well
    /// as the filter's.
    func replacePresented(_ windows: [WindowItem]) {
        presentedWindows = windows
    }

    /// Takes the panel down because a sent operation left its row behind.
    ///
    /// A row outliving the request is an interruption — the application's
    /// own dialog, most often — and not a failure: the operation was sent.
    /// Saying a dialog appeared would overclaim (a refusal leaves the row
    /// too), so the line says only what is known, that the row is still
    /// there. Leaving the panel up would keep the dialog hidden behind it.
    func closeAfterInterruptedOperation(operation: WindowOperation, appName: String, displayTitle: String) {
        dismissPanel()
        writeLine(
            "closed the panel (\(operation.logName) after: \(appName)/\(displayTitle) is still open)"
        )
    }
}
