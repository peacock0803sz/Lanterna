/// What can be done to the chosen row while a panel is up.
///
/// Closing and minimizing act on the window, quitting and hiding on the
/// application that owns it. The log names are one to one with the values, so
/// a line names an operation exactly one way.
enum WindowOperation: Equatable, Sendable, CaseIterable {
    case closeWindow
    case quitApplication
    case hideApplication
    case minimizeWindow

    /// The word the diagnostics line and the failure note print. Stable:
    /// people read and grep the diagnostics for these words, so they are
    /// `close` and not `closeWindow`.
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

extension ActivationFailure {
    /// The word the failure line prints. Stable: people read and grep the
    /// diagnostics for these words. A carried reason prints verbatim: the
    /// senders shape their own reasons, such as `error <value>`.
    var logDescription: String {
        switch self {
        case .windowGone:
            "window gone"
        case .applicationGone:
            "application gone"
        case .timedOut:
            "timed out"
        case let .other(reason):
            reason
        }
    }
}
