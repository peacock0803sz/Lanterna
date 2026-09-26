import ApplicationServices
import PrivateAPIs

/// Turns a shown row back into its accessibility element.
///
/// Shared by the switcher-shaped operations — closing and minimizing read
/// only the owning application's own window list, never a fresher one: the
/// target is what the appearance showed. One derivation of resolving for
/// both, so a row gone missing reads the same way in each; the switcher
/// keeps its own copy of the same steps.
struct WindowElementResolver: Sendable {
    static let messagingTimeout: Float = 1.0
    /// Answers slower than this are waits, not refusals. Half the messaging
    /// timeout leaves a wide margin on both sides; borrowed from the
    /// switcher, which draws the same line for the same code.
    static let unreachableAnswerCeiling: Duration = .milliseconds(500)

    /// What resolving came to. Apart from the outcome so a missing row stays
    /// distinct from a failed read all the way to the wording.
    enum Resolution {
        case element(AXUIElement)
        case failure(ActivationFailure)
    }

    private let createApplication: @Sendable (pid_t) -> AXUIElement
    private let setMessagingTimeout: @Sendable (AXUIElement, Float) -> AXError
    private let copyWindows: @Sendable (AXUIElement) -> (AXError, [AXUIElement]?)
    private let copyWindowID: @Sendable (AXUIElement) -> (AXError, CGWindowID)
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
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.createApplication = createApplication
        self.setMessagingTimeout = setMessagingTimeout
        self.copyWindows = copyWindows
        self.copyWindowID = copyWindowID
        self.now = now
    }

    /// Slow `cannotComplete` answers are waits, fast ones refusals.
    func waitedSince(_ instant: ContinuousClock.Instant) -> Bool {
        now() - instant >= Self.unreachableAnswerCeiling
    }

    /// Arms one element with the messaging timeout. Costs no round trip.
    func prepare(_ element: AXUIElement) -> Bool {
        setMessagingTimeout(element, Self.messagingTimeout) == .success
    }

    func resolve(_ target: ActivationTarget) -> Resolution {
        let application = createApplication(target.ownerProcessIdentifier)
        guard setMessagingTimeout(application, Self.messagingTimeout) == .success else {
            return .failure(.applicationGone)
        }
        let sentAt = now()
        let (windowsError, rawElements) = copyWindows(application)
        let elements: [AXUIElement]
        switch windowsError {
        case .success:
            // An application that answers its window list with something
            // that is not one cannot be read, and the reader's word for
            // that is kept: malformed answer.
            guard let rawElements else {
                return .failure(.other(reason: "malformed answer"))
            }
            elements = rawElements
        case .noValue:
            // No open windows, which the reader reads as an empty list: a
            // target of this application is gone rather than erroneous.
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

    /// What a failed list read means. Apart so resolving stays readable:
    /// the ceiling judges one message, whichever message it was.
    func listFailure(for error: AXError, since sentAt: ContinuousClock.Instant) -> ActivationFailure {
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

    /// One element against the target. Most elements are somebody else's row
    /// and are skipped; an answer about the application aborts the whole
    /// resolve instead. Anything else unreadable is skipped too: an element
    /// that cannot be told apart cannot condemn the take, and a target never
    /// matched is windowGone.
    private func match(_ element: AXUIElement, to target: ActivationTarget) -> ElementMatch {
        // The timeout rides with the element it protects: the setting
        // applies to the element it is made on, so every element is given
        // its own before its first message. One that cannot take it is
        // skipped like anything else unreadable.
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
}
