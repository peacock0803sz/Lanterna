import ApplicationServices
import PrivateAPIs

/// One window of one application, in a shape that can cross threads.
///
/// Deliberately free of AppKit types: the name and icon of the owning
/// application are joined back on the main thread.
struct WindowRecord: Sendable, Equatable {
    let windowID: CGWindowID
    let title: String
    let kind: WindowKind
    let isMinimized: Bool
}

/// The outcome of reading one application that answered.
struct ApplicationRead: Sendable {
    let records: [WindowRecord]
    /// Elements that were windows but reported no window-server id, counted for
    /// the diagnostics line so a silently missing row is still visible.
    let droppedWithoutID: Int
}

/// Why an application contributed no rows at all.
enum ReadFailure: Error, Sendable {
    case permissionMissing
    /// The application spent its budget, or answered `kAXErrorCannotComplete`
    /// to an attribute read, which means busy or wedged.
    case timedOut
    case unavailable(AXError)
}

/// Reads the windows of a single application.
///
/// A protocol because the enumerator's assembly rules — ordering, skipping,
/// fallbacks — are worth testing without a live accessibility connection.
protocol ApplicationWindowReading: Sendable {
    func read(processIdentifier: pid_t) -> Result<ApplicationRead, ReadFailure>
}

/// Reads windows over the accessibility API.
///
/// Runs on whichever thread calls it: accessibility calls are synchronous Mach
/// IPC and need no run loop. Each call makes and drops its own elements, so
/// nothing is shared between threads.
struct AXApplicationWindowReader: ApplicationWindowReading {
    /// What one element of an application's window list turned into.
    enum ElementOutcome: Equatable {
        case record(WindowRecord)
        case excluded
        case droppedWithoutID
    }

    /// Client-side ceiling on every message this reader sends.
    static let messagingTimeout: Float = 1.0

    private let setMessagingTimeout: @Sendable (AXUIElement, Float) -> AXError
    private let copyAttribute: @Sendable (AXUIElement, String) -> (AXError, CFTypeRef?)
    private let windowIdentifier: @Sendable (AXUIElement) -> (AXError, CGWindowID)

    /// The defaults talk to the real accessibility API. Tests replace them,
    /// because which error an application returns is precisely the behaviour
    /// being specified and no real application can be asked to return one.
    init(
        setMessagingTimeout: @escaping @Sendable (AXUIElement, Float) -> AXError = {
            AXUIElementSetMessagingTimeout($0, $1)
        },
        copyAttribute: @escaping @Sendable (AXUIElement, String) -> (AXError, CFTypeRef?) = { element, name in
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return (error, value)
        },
        windowIdentifier: @escaping @Sendable (AXUIElement) -> (AXError, CGWindowID) = { element in
            var identifier: CGWindowID = 0
            let error = _AXUIElementGetWindow(element, &identifier)
            return (error, identifier)
        }
    ) {
        self.setMessagingTimeout = setMessagingTimeout
        self.copyAttribute = copyAttribute
        self.windowIdentifier = windowIdentifier
    }

    /// Decides what one element of a window list becomes.
    ///
    /// Pure, so the whole rule table is testable. The order matters: an element
    /// that is not a listable window is excluded before its missing id can be
    /// counted as a loss, which is what keeps the Finder desktop out of the
    /// dropped tally.
    static func outcome(
        role: String?,
        subrole: String?,
        title: String,
        isMinimized: Bool,
        windowID: CGWindowID?
    ) -> ElementOutcome {
        guard let kind = WindowKind.classify(role: role, subrole: subrole) else {
            return .excluded
        }
        guard let windowID, windowID != 0 else {
            return .droppedWithoutID
        }
        return .record(
            WindowRecord(windowID: windowID, title: title, kind: kind, isMinimized: isMinimized)
        )
    }

    func read(processIdentifier: pid_t) -> Result<ApplicationRead, ReadFailure> {
        let application = AXUIElementCreateApplication(processIdentifier)
        if let failure = prepared(application) {
            return .failure(failure)
        }

        let windows: [AXUIElement]
        switch attribute(application, kAXWindowsAttribute) {
        case let .failure(failure):
            return .failure(failure)
        case let .success(value):
            // A regular application with no open window is a successful read of
            // an empty list, never a skipped application.
            windows = value as? [AXUIElement] ?? []
        }

        var records: [WindowRecord] = []
        var droppedWithoutID = 0
        for window in windows {
            switch outcome(for: window) {
            case let .failure(failure):
                // Half of a wedged application's windows is a worse list than
                // none of them, so the partial result is thrown away.
                return .failure(failure)
            case let .success(.record(record)):
                records.append(record)
            case .success(.excluded):
                continue
            case .success(.droppedWithoutID):
                droppedWithoutID += 1
            }
        }
        return .success(ApplicationRead(records: records, droppedWithoutID: droppedWithoutID))
    }

    private func outcome(for window: AXUIElement) -> Result<ElementOutcome, ReadFailure> {
        if let failure = prepared(window) {
            return .failure(failure)
        }

        let role: String?
        let subrole: String?
        let title: String
        let isMinimized: Bool
        switch attribute(window, kAXRoleAttribute) {
        case let .failure(failure): return .failure(failure)
        case let .success(value): role = value as? String
        }
        switch attribute(window, kAXSubroleAttribute) {
        case let .failure(failure): return .failure(failure)
        case let .success(value): subrole = value as? String
        }
        switch attribute(window, kAXTitleAttribute) {
        case let .failure(failure): return .failure(failure)
        case let .success(value): title = value as? String ?? ""
        }
        switch attribute(window, kAXMinimizedAttribute) {
        case let .failure(failure): return .failure(failure)
        case let .success(value): isMinimized = value as? Bool ?? false
        }

        return .success(
            Self.outcome(
                role: role,
                subrole: subrole,
                title: title,
                isMinimized: isMinimized,
                windowID: identifier(of: window)
            )
        )
    }

    /// Sets the client-side timeout before anything is sent to an element.
    ///
    /// A failure is not recoverable: sending anyway would fall back to the
    /// multi-second default and blow the per-application budget.
    private func prepared(_ element: AXUIElement) -> ReadFailure? {
        let error = setMessagingTimeout(element, Self.messagingTimeout)
        return error == .success ? nil : .unavailable(error)
    }

    /// Reads one attribute, separating "the application has no such value" from
    /// "the application could not answer".
    private func attribute(_ element: AXUIElement, _ name: String) -> Result<CFTypeRef?, ReadFailure> {
        let (error, value) = copyAttribute(element, name)
        switch error {
        case .success:
            return .success(value)
        case .noValue, .attributeUnsupported:
            // An absent value is an answer: an untitled window reports no title.
            return .success(nil)
        case .apiDisabled:
            return .failure(.permissionMissing)
        case .cannotComplete:
            return .failure(.timedOut)
        default:
            return .failure(.unavailable(error))
        }
    }

    /// The window-server id, or `nil` when the element has none.
    ///
    /// The one call whose failure is expected rather than exceptional: an
    /// element without an id is not a window worth listing, and says nothing
    /// about the health of the application that owns it.
    private func identifier(of element: AXUIElement) -> CGWindowID? {
        let (error, identifier) = windowIdentifier(element)
        return error == .success ? identifier : nil
    }
}
