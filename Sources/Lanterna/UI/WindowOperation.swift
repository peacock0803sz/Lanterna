/// What can be done to the chosen row while a panel is up.
///
/// Four operations and nothing else. Closing and minimizing act on the window,
/// quitting and hiding on the application that owns it. The log names are one
/// to one with the values, so a line names an operation exactly one way.
enum WindowOperation: Equatable, Sendable {
    case closeWindow
    case quitApplication
    case hideApplication
    case minimizeWindow

    /// The word the diagnostics line prints. Stable: the manual acceptance
    /// check greps these words, so they are `close` and not `closeWindow`.
    var logName: String {
        switch self {
        case .closeWindow:
            "close"
        case .quitApplication:
            "quit"
        case .hideApplication:
            "hide"
        case .minimizeWindow:
            "minimize"
        }
    }
}

/// What sending an operation came to.
///
/// `failed` carries the existing activation vocabulary rather than a new one:
/// a failure to act is told apart from a failure to switch nowhere on the
/// log line, and one vocabulary is what keeps it that way.
enum OperationOutcome: Equatable, Sendable {
    /// The row is gone from the list, or moved below the separator.
    case done
    /// Sent, yet the row is still there after waiting: an interruption such
    /// as the application's own save dialog, which the panel closes for.
    case interrupted
    /// Never sent. The list and the choice are wound back instead.
    case failed(ActivationFailure)
}
