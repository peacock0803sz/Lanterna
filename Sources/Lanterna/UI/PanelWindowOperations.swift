import ApplicationServices
import PrivateAPIs

/// Closes one window.
///
/// One method now; quitting, hiding and minimizing join as their stories
/// land. `nil` means the request was sent — whether it landed is what the
/// reconciling pass after it is for. A failure names why sending was not
/// even possible.
protocol WindowClosing: Sendable {
    func closeWindow(_ target: ActivationTarget) -> ActivationFailure?
}

/// Closes a window by pressing its close button.
///
/// Resolving (row to element) is the switcher's procedure: the target is
/// what the appearance showed, and only the owning application's own window
/// list is read. The last step is the only new one — the close button, one
/// level down, pressed the way a user presses it, so an application with
/// unsaved changes shows its own dialog instead of being forced.
///
/// Every seam is a closure defaulting to the real call, so tests script
/// answers no live application can be asked to give. The shape follows
/// `LiveWindowSwitcher`, which separates its sends the same way.
struct LiveWindowCloser: WindowClosing, Sendable {
    static let messagingTimeout: Float = 1.0
    /// Answers slower than this are waits, not refusals. Half the messaging
    /// timeout leaves a wide margin on both sides; borrowed from the
    /// switcher, which draws the same line for the same code.
    static let unreachableAnswerCeiling: Duration = .milliseconds(500)

    private let createApplication: @Sendable (pid_t) -> AXUIElement
    private let setMessagingTimeout: @Sendable (AXUIElement, Float) -> AXError
    private let copyWindows: @Sendable (AXUIElement) -> (AXError, [AXUIElement]?)
    private let copyWindowID: @Sendable (AXUIElement) -> (AXError, CGWindowID)
    private let copyChildren: @Sendable (AXUIElement) -> (AXError, [AXUIElement]?)
    private let attributeString: @Sendable (AXUIElement, String) -> (AXError, String?)
    private let press: @Sendable (AXUIElement) -> AXError
    private let now: @Sendable () -> ContinuousClock.Instant

    /// The defaults talk to the real accessibility API. Tests replace them,
    /// because which answer an application gives is precisely the behaviour
    /// being specified and no real application can be asked to give one.
    init(
        createApplication: @escaping @Sendable (pid_t) -> AXUIElement = {
            AXUIElementCreateApplication($0)
        },
        setMessagingTimeout: @escaping @Sendable (AXUIElement, Float) -> AXError = {
            AXUIElementSetMessagingTimeout($0, $1)
        },
        copyWindows: @escaping @Sendable (AXUIElement) -> (AXError, [AXUIElement]?) = { application in
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
            return (error, value as? [AXUIElement])
        },
        copyWindowID: @escaping @Sendable (AXUIElement) -> (AXError, CGWindowID) = { element in
            var windowID: CGWindowID = 0
            let error = _AXUIElementGetWindow(element, &windowID)
            return (error, windowID)
        },
        copyChildren: @escaping @Sendable (AXUIElement) -> (AXError, [AXUIElement]?) = { element in
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            return (error, value as? [AXUIElement])
        },
        attributeString: @escaping @Sendable (AXUIElement, String) -> (AXError, String?) = { element, name in
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return (error, value as? String)
        },
        press: @escaping @Sendable (AXUIElement) -> AXError = {
            AXUIElementPerformAction($0, kAXPressAction as CFString)
        },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.createApplication = createApplication
        self.setMessagingTimeout = setMessagingTimeout
        self.copyWindows = copyWindows
        self.copyWindowID = copyWindowID
        self.copyChildren = copyChildren
        self.attributeString = attributeString
        self.press = press
        self.now = now
    }

    func closeWindow(_ target: ActivationTarget) -> ActivationFailure? {
        // Resolve first, reading only the owning application's list. Never
        // a fresher list: the target is what the appearance showed.
        let resolved: AXUIElement
        switch resolve(target) {
        case let .element(element):
            resolved = element
        case let .failure(failure):
            return failure
        }
        // Then the close button, one level down. A window with none is a
        // failure, not a silent pass.
        let button: AXUIElement
        switch closeButton(of: resolved) {
        case let .button(element):
            button = element
        case let .failure(failure):
            return failure
        }
        return pressButton(button)
    }

    /// Slow `cannotComplete` answers are waits, fast ones refusals. The line
    /// is the switcher's: half the messaging timeout either way.
    private func waitedSince(_ instant: ContinuousClock.Instant) -> Bool {
        now() - instant >= Self.unreachableAnswerCeiling
    }

    private enum Resolution {
        case element(AXUIElement)
        case failure(ActivationFailure)
    }

    private func resolve(_ target: ActivationTarget) -> Resolution {
        let application = createApplication(target.ownerProcessIdentifier)
        guard setMessagingTimeout(application, Self.messagingTimeout) == .success else {
            return .failure(.applicationGone)
        }
        let sentAt = now()
        let (windowsError, rawElements) = copyWindows(application)
        let elements: [AXUIElement]
        switch windowsError {
        case .success:
            guard let rawElements else {
                return .failure(.other(reason: "malformed answer"))
            }
            elements = rawElements
        case .noValue:
            elements = []
        default:
            return .failure(listFailure(for: windowsError, since: sentAt))
        }
        for element in elements {
            switch match(element, to: target) {
            case .match:
                return .element(element)
            case .skip:
                continue
            case let .abort(failure):
                return .failure(failure)
            }
        }
        return .failure(.windowGone)
    }

    private func listFailure(for error: AXError, since sentAt: ContinuousClock.Instant) -> ActivationFailure {
        switch error {
        case .cannotComplete:
            return waitedSince(sentAt) ? .timedOut : .applicationGone
        case .apiDisabled:
            return .other(reason: "permission missing")
        case .invalidUIElement:
            return .applicationGone
        case let error:
            return .other(reason: "error \(error.rawValue)")
        }
    }

    private enum ElementMatch {
        case match
        case skip
        case abort(ActivationFailure)
    }

    private func match(_ element: AXUIElement, to target: ActivationTarget) -> ElementMatch {
        guard setMessagingTimeout(element, Self.messagingTimeout) == .success else {
            return .skip
        }
        let attemptAt = now()
        let (idError, windowID) = copyWindowID(element)
        switch idError {
        case .success:
            return windowID != 0 && windowID == target.id.windowID ? .match : .skip
        case .cannotComplete:
            return .abort(waitedSince(attemptAt) ? .timedOut : .applicationGone)
        case .apiDisabled:
            return .abort(.other(reason: "permission missing"))
        default:
            return .skip
        }
    }

    private enum ButtonSearch {
        case button(AXUIElement)
        case failure(ActivationFailure)
    }

    private func closeButton(of window: AXUIElement) -> ButtonSearch {
        guard setMessagingTimeout(window, Self.messagingTimeout) == .success else {
            return .failure(.other(reason: "error \(AXError.invalidUIElement.rawValue)"))
        }
        let sentAt = now()
        let (childrenError, children) = copyChildren(window)
        switch childrenError {
        case .success:
            break
        default:
            return .failure(listFailure(for: childrenError, since: sentAt))
        }
        for child in children ?? [] {
            guard setMessagingTimeout(child, Self.messagingTimeout) == .success else {
                continue
            }
            let (roleError, role) = attributeString(child, kAXRoleAttribute as String)
            let (subroleError, subrole) = attributeString(child, kAXSubroleAttribute as String)
            guard roleError == .success, subroleError == .success else {
                continue
            }
            if role == (kAXButtonRole as String), subrole == (kAXCloseButtonSubrole as String) {
                return .button(child)
            }
        }
        return .failure(.other(reason: "no close button"))
    }

    private func pressButton(_ button: AXUIElement) -> ActivationFailure? {
        let sentAt = now()
        switch press(button) {
        case .success:
            return nil
        case .cannotComplete:
            return waitedSince(sentAt)
                ? .timedOut : .other(reason: "error \(AXError.cannotComplete.rawValue)")
        case let error:
            return .other(reason: "error \(error.rawValue)")
        }
    }
}
