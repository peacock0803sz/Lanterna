import ApplicationServices
import PrivateAPIs

/// Closes one window.
///
/// `nil` means the request was sent — whether it landed is what the
/// reconciling pass after it is for. A failure names why the request did
/// not go through. A time-out on the press itself can come after the
/// application received the press, and it may still act on a press it was
/// slow to answer; a time-out while finding the window or its close button
/// comes before anything is pressed.
protocol WindowClosing: Sendable {
    func closeWindow(_ target: ActivationTarget) -> ActivationFailure?
}

/// Closes a window by pressing its close button.
///
/// Resolving (row to element) is the shared resolver's: the target is what
/// the appearance showed, and only the owning application's own window list
/// is read. The last step is the closer's own — the close button, one level
/// down, pressed the way a user presses it, so an application with unsaved
/// changes shows its own dialog instead of being forced.
///
/// Every seam is a closure defaulting to the real call, so tests script
/// answers no live application can be asked to give.
struct LiveWindowCloser: WindowClosing, Sendable {
    private let resolver: WindowElementResolver
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
        resolver = WindowElementResolver(
            createApplication: createApplication,
            setMessagingTimeout: setMessagingTimeout,
            copyWindows: copyWindows,
            copyWindowID: copyWindowID,
            now: now
        )
        self.copyChildren = copyChildren
        self.attributeString = attributeString
        self.press = press
        self.now = now
    }

    func closeWindow(_ target: ActivationTarget) -> ActivationFailure? {
        // Resolve first. Never a fresher list: the target is what the
        // appearance showed.
        let resolved: AXUIElement
        switch resolver.resolve(target) {
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

    private enum ButtonSearch {
        case button(AXUIElement)
        case failure(ActivationFailure)
    }

    private func closeButton(of window: AXUIElement) -> ButtonSearch {
        guard resolver.prepare(window) else {
            return .failure(.other(reason: "error \(AXError.invalidUIElement.rawValue)"))
        }
        let sentAt = now()
        let (childrenError, children) = copyChildren(window)
        switch childrenError {
        case .success:
            break
        default:
            return .failure(resolver.listFailure(for: childrenError, since: sentAt))
        }
        for child in children ?? [] {
            guard resolver.prepare(child) else {
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
            return resolver.waitedSince(sentAt)
                ? .timedOut : .other(reason: "error \(AXError.cannotComplete.rawValue)")
        case let error:
            return .other(reason: "error \(error.rawValue)")
        }
    }
}
