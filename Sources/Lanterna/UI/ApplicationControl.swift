import AppKit

/// What quitting and hiding ask of an application.
///
/// Behind a protocol because a test process wants to script the answer and
/// no live application can be asked to refuse on demand. The real
/// application answers below.
protocol ControllableApplication: Sendable {
    /// Asks for an ordinary termination, the way the user quits: the
    /// application's own dialog keeps unsaved changes. Never forced.
    func terminate() -> Bool
    /// Hides the application, the way its Hide menu item does.
    func hide() -> Bool
}

extension NSRunningApplication: ControllableApplication {}

/// Asks one application to quit, ordinarily.
///
/// `nil` means the request was sent — whether it landed is what the
/// reconciling pass after it is for. Forcing is not on offer anywhere here.
protocol ApplicationQuitting: Sendable {
    func quitApplication(processIdentifier: pid_t) -> ActivationFailure?
}

/// Hides one application.
protocol ApplicationHiding: Sendable {
    func hideApplication(processIdentifier: pid_t) -> ActivationFailure?
}

/// The real quitter: the application's own termination.
///
/// Called on the main actor, where the application's answers belong.
struct LiveApplicationQuitter: ApplicationQuitting, Sendable {
    private let findApplication: @Sendable (pid_t) -> (any ControllableApplication)?

    /// The default finds the live application. Tests hand one over, because
    /// refusing on demand is precisely the behaviour being specified.
    init(
        findApplication: @escaping @Sendable (pid_t) -> (any ControllableApplication)? = {
            NSRunningApplication(processIdentifier: $0)
        }
    ) {
        self.findApplication = findApplication
    }

    func quitApplication(processIdentifier: pid_t) -> ActivationFailure? {
        guard let application = findApplication(processIdentifier) else {
            return .applicationGone
        }
        return application.terminate() ? nil : .other(reason: "termination refused")
    }
}

/// The real hider: the application's own hiding.
///
/// Called on the main actor, where the application's answers belong.
struct LiveApplicationHider: ApplicationHiding, Sendable {
    private let findApplication: @Sendable (pid_t) -> (any ControllableApplication)?

    /// The default finds the live application. Tests hand one over, for the
    /// reason the quitter's does.
    init(
        findApplication: @escaping @Sendable (pid_t) -> (any ControllableApplication)? = {
            NSRunningApplication(processIdentifier: $0)
        }
    ) {
        self.findApplication = findApplication
    }

    func hideApplication(processIdentifier: pid_t) -> ActivationFailure? {
        guard let application = findApplication(processIdentifier) else {
            return .applicationGone
        }
        return application.hide() ? nil : .other(reason: "hide refused")
    }
}
