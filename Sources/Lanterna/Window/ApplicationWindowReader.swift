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
struct ApplicationRead: Sendable, Equatable {
    let records: [WindowRecord]
    /// Elements that were windows but reported no window-server id, counted for
    /// the diagnostics line so a silently missing row is still visible.
    let droppedWithoutID: Int
}

/// Why an application contributed no rows at all.
enum ReadFailure: Error, Sendable, Equatable {
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

/// How long one application may take before its windows are given up on.
///
/// The per-message timeout alone is not enough: an application that answers the
/// window list and then wedges would pay that timeout once per attribute, up to
/// five per window. Checking the total before each message is sent bounds the
/// wait at roughly the limit, and at worst one more message's timeout on top of
/// it when the last message starts just under the line.
struct ReadBudget {
    static let limit: Duration = .seconds(1)

    let startedAt: ContinuousClock.Instant

    func isExpired(at instant: ContinuousClock.Instant) -> Bool {
        instant - startedAt >= Self.limit
    }
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
    private let now: @Sendable () -> ContinuousClock.Instant

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
        },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.setMessagingTimeout = setMessagingTimeout
        self.copyAttribute = copyAttribute
        self.windowIdentifier = windowIdentifier
        self.now = now
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
        do {
            return try .success(records(of: processIdentifier))
        } catch {
            // Half of a wedged application's windows is a worse list than none
            // of them, so whatever was read so far goes with it.
            return .failure(error)
        }
    }

    private func records(of processIdentifier: pid_t) throws(ReadFailure) -> ApplicationRead {
        let budget = ReadBudget(startedAt: now())
        let application = AXUIElementCreateApplication(processIdentifier)
        try prepare(application)

        // A regular application with no open window is a successful read of an
        // empty list, never a skipped application.
        let windows = try attribute(application, kAXWindowsAttribute, within: budget)
            as? [AXUIElement] ?? []

        var records: [WindowRecord] = []
        var droppedWithoutID = 0
        for window in windows {
            switch try outcome(for: window, within: budget) {
            case let .record(record):
                records.append(record)
            case .excluded:
                continue
            case .droppedWithoutID:
                droppedWithoutID += 1
            }
        }
        return ApplicationRead(records: records, droppedWithoutID: droppedWithoutID)
    }

    private func outcome(
        for window: AXUIElement,
        within budget: ReadBudget
    ) throws(ReadFailure) -> ElementOutcome {
        try prepare(window)
        return try Self.outcome(
            role: attribute(window, kAXRoleAttribute, within: budget) as? String,
            subrole: attribute(window, kAXSubroleAttribute, within: budget) as? String,
            title: attribute(window, kAXTitleAttribute, within: budget) as? String ?? "",
            isMinimized: attribute(window, kAXMinimizedAttribute, within: budget) as? Bool ?? false,
            windowID: identifier(of: window, within: budget)
        )
    }

    /// Sets the client-side timeout before anything is sent to an element.
    ///
    /// Costs no round trip, so it is not charged to the budget. A failure is
    /// not recoverable: sending anyway would fall back to the multi-second
    /// default and blow the per-application budget.
    private func prepare(_ element: AXUIElement) throws(ReadFailure) {
        let error = setMessagingTimeout(element, Self.messagingTimeout)
        guard error == .success else {
            throw .unavailable(error)
        }
    }

    /// Reads one attribute, separating "the application has no such value" from
    /// "the application could not answer".
    private func attribute(
        _ element: AXUIElement,
        _ name: String,
        within budget: ReadBudget
    ) throws(ReadFailure) -> CFTypeRef? {
        guard !budget.isExpired(at: now()) else {
            throw .timedOut
        }
        let (error, value) = copyAttribute(element, name)
        switch error {
        case .success:
            return value
        case .noValue, .attributeUnsupported:
            // An absent value is an answer: an untitled window reports no title.
            return nil
        case .apiDisabled:
            throw .permissionMissing
        case .cannotComplete:
            throw .timedOut
        default:
            throw .unavailable(error)
        }
    }

    /// The window-server id, or `nil` when the element has none.
    ///
    /// The one call whose failure is expected rather than exceptional: an
    /// element without an id is not a window worth listing, and says nothing
    /// about the health of the application that owns it. Spending the budget
    /// still ends the read, since that is about the application, not the id.
    private func identifier(
        of element: AXUIElement,
        within budget: ReadBudget
    ) throws(ReadFailure) -> CGWindowID? {
        guard !budget.isExpired(at: now()) else {
            throw .timedOut
        }
        let (error, identifier) = windowIdentifier(element)
        return error == .success ? identifier : nil
    }
}
