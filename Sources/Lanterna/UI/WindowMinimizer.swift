import ApplicationServices
import PrivateAPIs

/// Minimizes one window.
///
/// `nil` means the request was sent — whether it landed is what the
/// reconciling pass after it is for. A failure names why the request did
/// not go through. A time-out on writing the flag itself is the one failure
/// that may have reached the application, which may still act on a write
/// it was slow to answer; a time-out while finding the window comes before
/// anything is written.
protocol WindowMinimizing: Sendable {
    func minimizeWindow(_ target: ActivationTarget) -> ActivationFailure?
}

/// Minimizes a window by writing its minimized flag.
///
/// Resolving (row to element) is the shared resolver's, the way closing
/// resolves. The last step is the mirror of what the switcher writes to
/// unminimize: the same attribute, the other value.
///
/// Every seam is a closure defaulting to the real call, so tests script
/// answers no live application can be asked to give.
struct LiveWindowMinimizer: WindowMinimizing, Sendable {
    private let resolver: WindowElementResolver
    private let setMinimized: @Sendable (AXUIElement, Bool) -> AXError
    private let now: @Sendable () -> ContinuousClock.Instant

    /// The defaults talk to the real accessibility API. Tests replace them,
    /// because which answer an application gives is precisely the behaviour
    /// being specified and no real application can be asked to give one.
    init(
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
        setMinimized: @escaping @Sendable (AXUIElement, Bool) -> AXError = {
            AXUIElementSetAttributeValue($0, kAXMinimizedAttribute as CFString, $1 as CFTypeRef)
        },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        resolver = WindowElementResolver(copyWindows: copyWindows, copyWindowID: copyWindowID, now: now)
        self.setMinimized = setMinimized
        self.now = now
    }

    func minimizeWindow(_ target: ActivationTarget) -> ActivationFailure? {
        // Resolve first. Never a fresher list: the target is what the
        // appearance showed.
        let resolved: AXUIElement
        switch resolver.resolve(target) {
        case let .element(element):
            resolved = element
        case let .failure(failure):
            return failure
        }
        let sentAt = now()
        switch setMinimized(resolved, true) {
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
