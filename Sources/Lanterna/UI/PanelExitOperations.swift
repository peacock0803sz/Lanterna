/// The ways out that reconciling an operation needs, and the take-down for
/// the app's own tidying beside them.
///
/// Split from the exit, which decides when a panel comes down with what
/// line. Swapping the shown list and closing for an interruption are the
/// operations' questions, and they grow beside the operations rather than
/// inside a file already close to the length the linter allows; the
/// take-down moved out with them to keep that file within it.
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

    /// Swaps the list an appearance is showing, whenever an operation moves
    /// the look, reconciles it against a fresher list or winds it back.
    /// Commits keep naming rows of what the panel showed last, so the swap
    /// has to reach this list as well as the filter's.
    func replacePresented(_ windows: [WindowItem]) {
        presentedWindows = windows
    }

    /// Takes the panel down because no reconciling pass confirmed a sent
    /// operation: each pass still found the rows the operation should have
    /// changed, or could not decide, in any mix.
    ///
    /// That is an interruption and not a failure: the operation was sent.
    /// The application's own dialog can be why, but a refusal or a pass
    /// that never read the application looks the same from here, so the
    /// line says only what is known, that the change was not confirmed.
    /// Leaving the panel up would keep any dialog hidden behind it.
    func closeAfterInterruptedOperation(operation: WindowOperation, appName: String, displayTitle: String) {
        dismissPanel()
        writeLine(
            "closed the panel (\(operation.logName) not confirmed: \(appName)/\(displayTitle))"
        )
    }
}
