import ApplicationServices
import Darwin
import PrivateAPIs

/// Reads the frontmost window's identity of one application.
///
/// Called once per activation, on the turn the notification arrived on, so a
/// conforming type must answer promptly rather than queue: the reading sits
/// outside every measured span, but the next appearance sorts on what it
/// wrote down.
///
/// A protocol because the entry below — record or record nothing — is worth
/// testing without a live accessibility connection. Lives in a file of its
/// own because the window reader it would have joined is already long enough
/// that adding to it would put it over the file limit.
protocol FocusedWindowReading: Sendable {
    /// The frontmost window's id, or nothing when the read fails. A zero id
    /// reads as nothing too: it is what the id fetch reports for "none", and
    /// a row's identity is built from this value.
    func focusedWindowID(of processIdentifier: pid_t) -> CGWindowID?
}

/// Reads the frontmost window over the accessibility API.
///
/// Runs on whichever thread calls it: accessibility calls are synchronous Mach
/// IPC and need no run loop. Each call makes and drops its own elements, so
/// nothing is shared between calls.
struct AXFocusedWindowReader: FocusedWindowReading {
    /// Client-side ceiling on every message this reader sends, matching the
    /// charter's messaging timeout: a wedged application costs at most this
    /// long, once, per activation.
    static let messagingTimeout: Float = 1.0

    private let setMessagingTimeout: @Sendable (AXUIElement, Float) -> AXError
    private let copyFocusedWindow: @Sendable (AXUIElement) -> (AXError, AXUIElement?)
    private let copyWindowID: @Sendable (AXUIElement) -> (AXError, CGWindowID)

    /// The defaults talk to the real accessibility API. Tests replace them,
    /// because which answer an application gives is precisely the behaviour
    /// being specified and no real application can be asked to fail one.
    init(
        setMessagingTimeout: @escaping @Sendable (AXUIElement, Float) -> AXError = {
            AXUIElementSetMessagingTimeout($0, $1)
        },
        copyFocusedWindow: @escaping @Sendable (AXUIElement) -> (AXError, AXUIElement?) = { element in
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(
                element, kAXFocusedWindowAttribute as CFString, &value
            )
            // The attribute answers with the focused element on success. The
            // type is checked before converting: a conditional cast cannot
            // express this (it always succeeds on CoreFoundation types), and
            // a forced one would trap on a broken contract instead of
            // reading it as no focused window.
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return (error, nil)
            }
            return (error, unsafeDowncast(value, to: AXUIElement.self))
        },
        copyWindowID: @escaping @Sendable (AXUIElement) -> (AXError, CGWindowID) = { element in
            var windowID: CGWindowID = 0
            let error = _AXUIElementGetWindow(element, &windowID)
            return (error, windowID)
        }
    ) {
        self.setMessagingTimeout = setMessagingTimeout
        self.copyFocusedWindow = copyFocusedWindow
        self.copyWindowID = copyWindowID
    }

    func focusedWindowID(of processIdentifier: pid_t) -> CGWindowID? {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard setMessagingTimeout(application, Self.messagingTimeout) == .success else {
            return nil
        }
        let (focusError, focused) = copyFocusedWindow(application)
        guard focusError == .success, let focused else {
            return nil
        }
        // The timeout rides with the element it protects: messaging timeouts
        // are per element, so the id fetch below needs its own. Without it a
        // wedged application would answer on the multi-second default while
        // the main queue handles the activation.
        guard setMessagingTimeout(focused, Self.messagingTimeout) == .success else {
            return nil
        }
        let (idError, windowID) = copyWindowID(focused)
        guard idError == .success, windowID != 0 else {
            return nil
        }
        return windowID
    }
}

/// Reads the frontmost window of an application and records it as an external
/// activation, doing nothing when the read fails, names this process, or is
/// the commit's own echo coming back.
///
/// The whole outside entry in one place: recording from anywhere else would
/// be a second entry to the same memory, and a failure that recorded would
/// turn every unreachable application into a use that never happened.
///
/// Runs synchronously on the notification turn by design: the record must
/// land before the next appearance sorts, which an off-main read cannot
/// promise. The wait is bounded by the messaging timeout (at most two timed
/// reads), and a wedged frontmost application leaves the user with worse
/// than a late panel. Same-application moves without an activation carry
/// no notice and are therefore never recorded here; that scope is deliberate.
@MainActor
func recordExternalActivation(
    of processIdentifier: pid_t,
    excluding ownProcessIdentifier: pid_t,
    reading: any FocusedWindowReading,
    into tracker: MRUTracker
) {
    guard processIdentifier != ownProcessIdentifier else {
        return
    }
    guard tracker.shouldRecordExternal(for: processIdentifier) else {
        return
    }
    guard let windowID = reading.focusedWindowID(of: processIdentifier) else {
        return
    }
    tracker.record(
        WindowItem.Identifier(windowID: windowID),
        ownerProcessIdentifier: processIdentifier,
        origin: .external
    )
}
