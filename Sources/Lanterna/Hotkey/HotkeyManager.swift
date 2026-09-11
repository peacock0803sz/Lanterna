import Carbon.HIToolbox
import Foundation

/// Stamped on every hotkey this app registers, spelling "LTRN". A press
/// carrying anything else belongs to some other handler on the same target and
/// is left alone.
private let hotkeySignature: OSType = 0x4C54_524E

/// What one round of hotkey registration achieved.
///
/// The two combinations are registered separately and either can fail on its
/// own, so the result is a pair of lists rather than a yes or no. This is also
/// the only place the launch diagnostics line is worded, which keeps the shape
/// of that line testable while the registration itself is not.
struct HotkeyRegistrationOutcome: Sendable {
    /// A combination the system would not hand over, and the status it gave.
    struct Failure: Sendable {
        let combination: HotkeyCombination
        let status: OSStatus
    }

    let registered: [HotkeyCombination]
    let failures: [Failure]

    /// `assert` rather than `precondition`: a combination on both lists, or
    /// on neither, is loud in debug builds and under test, but a misworded
    /// line must never take the app down in release — an app that cannot
    /// claim its hotkeys is the very thing this line exists to report.
    init(registered: [HotkeyCombination], failures: [Failure]) {
        // Two clauses because neither sees the other's case: a combination
        // missing from both lists leaves the set short of the whole, while
        // one on both lists or named twice leaves the count over it without
        // the set noticing.
        let accounted = registered + failures.map(\.combination)
        assert(
            Set(accounted) == Set(HotkeyCombination.all)
                && accounted.count == HotkeyCombination.all.count,
            "every combination must be registered or failed, exactly once"
        )
        self.registered = registered
        self.failures = failures
    }

    /// Nothing was registered, so there is no way left to reach the switcher
    /// and no reason to stay running.
    var isTotalFailure: Bool {
        registered.isEmpty
    }

    /// The one line written after registration: what was taken, what was not
    /// and why, and whether that leaves anything to run for.
    var summaryLine: String {
        var segments: [String] = []
        if !registered.isEmpty {
            segments.append("registered " + registered.map(\.name).joined(separator: ", "))
        }
        if !failures.isEmpty {
            let reasons = failures.map { "\($0.combination.name) (error \($0.status))" }
            segments.append("could not register " + reasons.joined(separator: ", "))
        }
        if isTotalFailure {
            segments.append("no hotkey registered, exiting")
        }
        return segments.joined(separator: "; ")
    }
}

/// Holds the switcher's hotkeys with Carbon and turns a press into a call.
///
/// A class rather than a value: Carbon is handed a raw pointer to the owner
/// and hands it back on every press, so something has to stay at that address
/// for as long as the handler is installed.
@MainActor
final class HotkeyManager {
    /// Called for each press, with the combination and how long the press took
    /// to reach this process.
    ///
    /// `fileprivate` because the C callback below is a free function — it
    /// cannot be a method, having nowhere to keep a `self` — and free
    /// functions are outside a `private` member's reach.
    fileprivate let onPress: @MainActor (HotkeyCombination, Duration?) -> Void

    private var eventHandler: EventHandlerRef?
    /// Only the ones that were actually taken. The combination is kept
    /// alongside the reference so what is held can be read off the state
    /// rather than inferred.
    private var hotKeys: [(HotkeyCombination, EventHotKeyRef)] = []

    init(onPress: @escaping @MainActor (HotkeyCombination, Duration?) -> Void) {
        self.onPress = onPress
    }

    /// Installs the handler and claims both combinations.
    ///
    /// Called once at launch. Either combination can be refused on its own, so
    /// the result says which were taken rather than whether the call worked.
    func register() -> HotkeyRegistrationOutcome {
        if let status = installHandler() {
            // A hotkey with no handler behind it would swallow the press and
            // do nothing with it, which is worse than not claiming it, so none
            // is claimed.
            return HotkeyRegistrationOutcome(
                registered: [],
                failures: HotkeyCombination.all.map {
                    HotkeyRegistrationOutcome.Failure(combination: $0, status: status)
                }
            )
        }

        var registered: [HotkeyCombination] = []
        var failures: [HotkeyRegistrationOutcome.Failure] = []
        for combination in HotkeyCombination.all {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                combination.keyCode,
                combination.carbonModifiers,
                EventHotKeyID(signature: hotkeySignature, id: combination.id),
                GetEventDispatcherTarget(),
                // Shared rather than exclusive. Exclusive would refuse the
                // registration whenever another switcher already holds the
                // combination, which would mean this app cannot start
                // alongside one; shared lets both run and both answer.
                OptionBits(kEventHotKeyNoOptions),
                &reference
            )
            if status == noErr, let reference {
                hotKeys.append((combination, reference))
                registered.append(combination)
            } else {
                failures.append(
                    HotkeyRegistrationOutcome.Failure(combination: combination, status: status)
                )
            }
        }
        return HotkeyRegistrationOutcome(registered: registered, failures: failures)
    }

    /// Gives every claimed combination back and takes the handler down.
    func unregister() {
        for (_, reference) in hotKeys {
            UnregisterEventHotKey(reference)
        }
        hotKeys.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// Installs the one handler both hotkeys report to, or returns why it
    /// could not be installed. Doing nothing and returning `nil` when one is
    /// already installed keeps a second `register()` from stacking handlers.
    private func installHandler() -> OSStatus? {
        guard eventHandler == nil else {
            return nil
        }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // `GetEventDispatcherTarget()` and not `GetEventMonitorTarget()`: the
        // monitor target sees raw key events and so requires the user to grant
        // access for assistive devices, while the dispatcher target requires
        // nothing. Taking Cmd+Tab over therefore asks for no permission the
        // app does not already hold.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            handleHotkeyEvent,
            1,
            &spec,
            context,
            &eventHandler
        )
        return status == noErr ? nil : status
    }
}

/// Carbon's callback for a press.
///
/// A `@convention(c)` function captures nothing, so the manager arrives
/// through `userData`; that pointer is the only channel there is.
///
/// The work happens here and not on a hop to the main queue. The handler has
/// to return an `OSStatus` saying whether the press was consumed, and an
/// asynchronous hop would have to answer that before knowing — and would put a
/// run-loop turn between the press and the panel, on the one path with a time
/// budget.
private func handleHotkeyEvent(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var identifier = EventHotKeyID()
    let read = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard read == noErr,
          identifier.signature == hotkeySignature,
          GetEventKind(event) == UInt32(kEventHotKeyPressed),
          let combination = HotkeyCombination(id: identifier.id)
    else {
        return OSStatus(eventNotHandledErr)
    }

    // Worked out before the hop, because `EventRef` is not `Sendable` and
    // cannot be carried into the closure. Both readings are seconds since boot
    // on the same clock, so the subtraction stands on its own with no
    // conversion in between.
    let delay = Duration.seconds(GetCurrentEventTime() - GetEventTime(event))

    // Resolved out here rather than inside the closure: a raw pointer belongs
    // to whatever region the caller is in and cannot be sent across, while the
    // manager it points at is main-actor isolated and so is safe to hand over.
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

    // Carbon does not promise which thread runs a handler. The dispatcher
    // target runs it on whichever thread pumps the event loop, which under a
    // running application is the main one, but the guard is what makes the
    // assumption below sound rather than hopeful.
    guard Thread.isMainThread else {
        return OSStatus(eventNotHandledErr)
    }
    MainActor.assumeIsolated {
        manager.onPress(combination, delay)
    }
    return noErr
}
