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

    /// Zero is what the id fetch reports for "none", and a row's identity is
    /// built from this value. `AXApplicationWindowReader.outcome` counts such
    /// an element as dropped before a record exists, so one getting this far
    /// is a programming error.
    init(windowID: CGWindowID, title: String, kind: WindowKind, isMinimized: Bool) {
        precondition(windowID != 0, "a window record needs a window-server id")
        self.windowID = windowID
        self.title = title
        self.kind = kind
        self.isMinimized = isMinimized
    }
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
    /// only after roughly the messaging timeout, which means busy or wedged.
    /// The same code answered at once is `unavailable`: nothing was waited
    /// for, the application has quit or is not reachable yet.
    case timedOut
    /// The application answered the window list with something that is not
    /// one. The call itself succeeded, so there is no `AXError` to report.
    case malformedAnswer
    case unavailable(AXError)
}

extension ReadFailure: CustomStringConvertible {
    /// The reason as the diagnostics line prints it. The manual acceptance
    /// check greps these words, so they are stable.
    var description: String {
        switch self {
        case .timedOut:
            "timed out"
        case .permissionMissing:
            "permission missing"
        case .malformedAnswer:
            "malformed answer"
        case let .unavailable(error):
            "error \(error.rawValue)"
        }
    }
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

    /// How fast a `kAXErrorCannotComplete` must come back to count as a refusal
    /// rather than a wait.
    ///
    /// The API answers with that one code both when the message timed out and
    /// when the peer cannot be reached at all — it quit, or its accessibility
    /// server is not up yet. A timeout takes the whole messaging timeout to
    /// come back, so an answer in a fraction of it was a refusal, not a wait.
    /// Half the timeout leaves a wide margin on both sides.
    static let unreachableAnswerCeiling: Duration = .seconds(Double(messagingTimeout) / 2)

    private let setMessagingTimeout: @Sendable (AXUIElement, Float) -> AXError
    private let copyAttribute: @Sendable (AXUIElement, String) -> (AXError, CFTypeRef?)
    private let copyWindowID: @Sendable (AXUIElement) -> (AXError, CGWindowID)
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
        copyWindowID: @escaping @Sendable (AXUIElement) -> (AXError, CGWindowID) = { element in
            var windowID: CGWindowID = 0
            let error = _AXUIElementGetWindow(element, &windowID)
            return (error, windowID)
        },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.setMessagingTimeout = setMessagingTimeout
        self.copyAttribute = copyAttribute
        self.copyWindowID = copyWindowID
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
            return try .success(applicationRead(of: processIdentifier))
        } catch {
            // Half of a wedged application's windows is a worse list than none
            // of them, so whatever was read so far goes with it.
            return .failure(error)
        }
    }

    private func applicationRead(of processIdentifier: pid_t) throws(ReadFailure) -> ApplicationRead {
        let budget = ReadBudget(startedAt: now())
        let application = AXUIElementCreateApplication(processIdentifier)
        try prepare(application)
        let windows = try windowElements(of: application, within: budget)

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

    /// The application's window list, empty when nothing is open.
    ///
    /// Every live application answers this attribute with an array, an empty
    /// one included, so any other answer means the application cannot be
    /// read, not that it has no windows. Folding it into an empty list would
    /// count the application without a row and without a reason, the one gap
    /// the summary line exists to close. "No value" alone is accepted as
    /// nothing open.
    private func windowElements(
        of application: AXUIElement,
        within budget: ReadBudget
    ) throws(ReadFailure) -> [AXUIElement] {
        let (error, value) = try send(kAXWindowsAttribute, to: application, within: budget)
        switch error {
        case .success:
            guard let windows = value as? [AXUIElement] else {
                throw .malformedAnswer
            }
            return windows
        case .noValue:
            return []
        default:
            // Only `attributeUnsupported` gets this far: the accessibility
            // server has no window list to give.
            throw .unavailable(error)
        }
    }

    private func outcome(
        for window: AXUIElement,
        within budget: ReadBudget
    ) throws(ReadFailure) -> ElementOutcome {
        try prepare(window)
        let role = try attribute(window, kAXRoleAttribute, within: budget) as? String
        let subrole = try attribute(window, kAXSubroleAttribute, within: budget) as? String
        // The rule table's first check, applied as soon as it can be: every
        // message is a round trip, and a failing one discards the whole
        // application, so an element that will not become a row is asked
        // nothing more.
        guard WindowKind.classify(role: role, subrole: subrole) != nil else {
            return .excluded
        }
        return try Self.outcome(
            role: role,
            subrole: subrole,
            title: attribute(window, kAXTitleAttribute, within: budget) as? String ?? "",
            isMinimized: attribute(window, kAXMinimizedAttribute, within: budget) as? Bool ?? false,
            windowID: windowID(of: window, within: budget)
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

    /// Reads one attribute, or `nil` when the element has no such value. An
    /// absent value is an answer: an untitled window reports no title.
    private func attribute(
        _ element: AXUIElement,
        _ name: String,
        within budget: ReadBudget
    ) throws(ReadFailure) -> CFTypeRef? {
        let (error, value) = try send(name, to: element, within: budget)
        return error == .success ? value : nil
    }

    /// Sends one attribute read, separating the answers that are about the
    /// attribute from the failures that are about the application.
    ///
    /// `success`, `noValue` and `attributeUnsupported` come back as answered:
    /// what each means depends on what was asked. Everything else ends the
    /// read.
    private func send(
        _ name: String,
        to element: AXUIElement,
        within budget: ReadBudget
    ) throws(ReadFailure) -> (AXError, CFTypeRef?) {
        let sentAt = now()
        guard !budget.isExpired(at: sentAt) else {
            throw .timedOut
        }
        let (error, value) = copyAttribute(element, name)
        switch error {
        case .success, .noValue, .attributeUnsupported:
            return (error, value)
        case .apiDisabled:
            throw .permissionMissing
        case .cannotComplete:
            throw Self.failure(forCannotCompleteAfter: now() - sentAt)
        default:
            throw .unavailable(error)
        }
    }

    /// The window-server id, or `nil` when the element has none.
    ///
    /// The one call whose failure is expected rather than exceptional: an
    /// element without an id — `illegalArgument`, in practice — is not a
    /// window worth listing, and says nothing about the health of the
    /// application that owns it. `cannotComplete` is the exception. The fetch
    /// is a round trip like any attribute read, and reading its timeout as
    /// "no id" would turn a hung application's last window into a dropped
    /// element and the rest into the partial list that discarding the whole
    /// application exists to avoid. Spending the budget ends the read for the
    /// same reason.
    private func windowID(
        of element: AXUIElement,
        within budget: ReadBudget
    ) throws(ReadFailure) -> CGWindowID? {
        let sentAt = now()
        guard !budget.isExpired(at: sentAt) else {
            throw .timedOut
        }
        let (error, windowID) = copyWindowID(element)
        switch error {
        case .success:
            return windowID
        case .cannotComplete:
            throw Self.failure(forCannotCompleteAfter: now() - sentAt)
        default:
            return nil
        }
    }

    /// What a `kAXErrorCannotComplete` that took `elapsed` to come back means:
    /// a wait that ran out, or a refusal that never waited.
    private static func failure(forCannotCompleteAfter elapsed: Duration) -> ReadFailure {
        elapsed >= unreachableAnswerCeiling ? .timedOut : .unavailable(.cannotComplete)
    }
}
