import AppKit
import ApplicationServices
import PrivateAPIs

/// What a commit takes: the row it named, as identity, owner and names.
///
/// A value, not the row itself. `WindowItem` carries an `NSImage` and so is
/// neither `Equatable` nor `Sendable`, while switching needs only who owns
/// which window and what to call it on the log line. The names travel along
/// for the wording; nothing that decides is read off them.
struct ActivationTarget: Equatable, Sendable {
    let id: WindowItem.Identifier
    let ownerProcessIdentifier: pid_t
    let appName: String
    let displayTitle: String
    /// As of the appearance that named it, for the log line only. Whether to
    /// unminimize is never decided off this: unminimizing is written
    /// unconditionally, a write with no effect when there is nothing to undo.
    let isMinimized: Bool
}

/// Why a switch did not happen. The smallest vocabulary that tells the four
/// apart on the log line; anything else goes in `other` until it earns a case.
enum ActivationFailure: Equatable, Sendable {
    case windowGone
    case applicationGone
    case timedOut
    case other(reason: String)
}

/// What trying a target came to.
enum ActivationOutcome: Equatable, Sendable {
    case switched
    case failed(ActivationFailure)
}

/// The one entrance the commit paths call. Takes a single target rather than
/// a list, so resolving off a fresher list at commit time has nowhere to go.
protocol WindowSwitching: Sendable {
    func switchTo(_ target: ActivationTarget) -> ActivationOutcome
}

/// Talks to the real accessibility API, in the order the contract pins down:
/// activate, unminimize, raise. Resolving (row to element) happens first and
/// reads nothing but the target application's own window list.
///
/// Every seam is a closure defaulting to the real call, so tests script
/// answers no live application can be asked to give. The shape follows
/// `AXApplicationWindowReader`, which separates its sends the same way.
struct LiveWindowSwitcher: WindowSwitching, Sendable {
    static let messagingTimeout: Float = 1.0
    /// Answers slower than this are waits, not refusals. Half the messaging
    /// timeout leaves a wide margin on both sides; borrowed from the reader,
    /// which draws the same line for the same code.
    static let unreachableAnswerCeiling: Duration = .milliseconds(500)

    private let createApplication: @Sendable (pid_t) -> AXUIElement
    private let setMessagingTimeout: @Sendable (AXUIElement, Float) -> AXError
    private let copyWindows: @Sendable (AXUIElement) -> (AXError, [AXUIElement])
    private let copyWindowID: @Sendable (AXUIElement) -> (AXError, CGWindowID)
    private let activateApplication: @Sendable (pid_t) -> ApplicationActivation
    private let setMinimized: @Sendable (AXUIElement, Bool) -> AXError
    private let raiseWindow: @Sendable (AXUIElement) -> AXError
    private let now: @Sendable () -> ContinuousClock.Instant

    /// How activating answered. Apart from the outcome so tests can script
    /// each without a live application.
    enum ApplicationActivation: Equatable, Sendable {
        case activated
        case missing
        case refused
    }

    /// The defaults talk to the real accessibility API. Tests replace them.
    init(
        createApplication: @escaping @Sendable (pid_t) -> AXUIElement = {
            AXUIElementCreateApplication($0)
        },
        setMessagingTimeout: @escaping @Sendable (AXUIElement, Float) -> AXError = {
            AXUIElementSetMessagingTimeout($0, $1)
        },
        copyWindows: @escaping @Sendable (AXUIElement) -> (AXError, [AXUIElement]) = { application in
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
            return (error, value as? [AXUIElement] ?? [])
        },
        copyWindowID: @escaping @Sendable (AXUIElement) -> (AXError, CGWindowID) = { element in
            var windowID: CGWindowID = 0
            let error = _AXUIElementGetWindow(element, &windowID)
            return (error, windowID)
        },
        activateApplication: @escaping @Sendable (pid_t) -> ApplicationActivation = { pid in
            guard let application = NSRunningApplication(processIdentifier: pid) else { return .missing }
            return application.activate() ? .activated : .refused
        },
        setMinimized: @escaping @Sendable (AXUIElement, Bool) -> AXError = {
            AXUIElementSetAttributeValue($0, kAXMinimizedAttribute as CFString, $1 as CFTypeRef)
        },
        raiseWindow: @escaping @Sendable (AXUIElement) -> AXError = {
            AXUIElementPerformAction($0, kAXRaiseAction as CFString)
        },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.createApplication = createApplication
        self.setMessagingTimeout = setMessagingTimeout
        self.copyWindows = copyWindows
        self.copyWindowID = copyWindowID
        self.activateApplication = activateApplication
        self.setMinimized = setMinimized
        self.raiseWindow = raiseWindow
        self.now = now
    }

    func switchTo(_ target: ActivationTarget) -> ActivationOutcome {
        // 0. Resolve the row back to an element, reading only the owning
        // application's list. Never a fresher list: the target is what the
        // appearance showed.
        let resolved: AXUIElement
        switch resolve(target) {
        case let .element(element):
            resolved = element
        case let .failure(outcome):
            return outcome
        }
        // 1. Activate first, so a hidden application is unhidden before any
        // window of it is touched.
        if let failure = activate(target) {
            return .failed(failure)
        }
        // 2. Unminimize unconditionally. Writing false where nothing is
        // minimized has no effect, which is cheaper than a round trip asking.
        if let failure = unminimize(resolved) {
            return .failed(failure)
        }
        // 3. Raise. Anything left standing here is the window to take.
        if let failure = raise(resolved) {
            return .failed(failure)
        }
        return .switched
    }

    /// Slow `cannotComplete` answers are waits, fast ones refusals. The line
    /// is the reader's: half the messaging timeout either way.
    private func waitedSince(_ instant: ContinuousClock.Instant) -> Bool {
        now() - instant >= Self.unreachableAnswerCeiling
    }

    /// What resolving came to. Apart from the outcome so a missing row stays
    /// distinct from a failed read all the way to the wording.
    private enum Resolution {
        case element(AXUIElement)
        case failure(ActivationOutcome)
    }

    private func resolve(_ target: ActivationTarget) -> Resolution {
        let application = createApplication(target.ownerProcessIdentifier)
        guard setMessagingTimeout(application, Self.messagingTimeout) == .success else {
            return .failure(.failed(.applicationGone))
        }
        let sentAt = now()
        let (windowsError, elements) = copyWindows(application)
        switch windowsError {
        case .success:
            break
        case .cannotComplete:
            return .failure(waitedSince(sentAt) ? .failed(.timedOut) : .failed(.applicationGone))
        case .apiDisabled:
            return .failure(.failed(.other(reason: "permission missing")))
        case .invalidUIElement:
            return .failure(.failed(.applicationGone))
        case let error:
            return .failure(.failed(.other(reason: "error \(error.rawValue)")))
        }
        for element in elements {
            switch match(element, to: target, since: sentAt) {
            case .match:
                return .element(element)
            case .skip:
                continue
            case let .abort(outcome):
                return .failure(outcome)
            }
        }
        return .failure(.failed(.windowGone))
    }

    /// One element against the target. Most elements are somebody else's row
    /// and are skipped; an answer about the application aborts the whole
    /// resolve instead.
    private enum ElementMatch {
        case match
        case skip
        case abort(ActivationOutcome)
    }

    private func match(
        _ element: AXUIElement,
        to target: ActivationTarget,
        since sentAt: ContinuousClock.Instant
    ) -> ElementMatch {
        let (idError, windowID) = copyWindowID(element)
        switch idError {
        case .success:
            return windowID != 0 && windowID == target.id.windowID ? .match : .skip
        case .cannotComplete:
            return .abort(waitedSince(sentAt) ? .failed(.timedOut) : .failed(.applicationGone))
        case .apiDisabled:
            return .abort(.failed(.other(reason: "permission missing")))
        default:
            return .skip
        }
    }

    private func activate(_ target: ActivationTarget) -> ActivationFailure? {
        switch activateApplication(target.ownerProcessIdentifier) {
        case .activated:
            return nil
        case .missing:
            return .applicationGone
        case .refused:
            return .other(reason: "activation refused")
        }
    }

    /// One AX write with the timeout drawn the same way everywhere: a slow
    /// `cannotComplete` is a wait, anything fast a plain error to name.
    private func write(
        _ element: AXUIElement,
        _ action: @Sendable (AXUIElement) -> AXError
    ) -> ActivationFailure? {
        let sentAt = now()
        switch action(element) {
        case .success:
            return nil
        case .cannotComplete:
            return waitedSince(sentAt)
                ? .timedOut : .other(reason: "error \(AXError.cannotComplete.rawValue)")
        case let error:
            return .other(reason: "error \(error.rawValue)")
        }
    }

    private func unminimize(_ element: AXUIElement) -> ActivationFailure? {
        write(element) { setMinimized($0, false) }
    }

    private func raise(_ element: AXUIElement) -> ActivationFailure? {
        write(element, raiseWindow)
    }
}
