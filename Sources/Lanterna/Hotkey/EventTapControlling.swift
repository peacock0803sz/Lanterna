import CoreGraphics
import Foundation

/// The operations on a system-wide event tap that the monitor needs.
///
/// Behind a protocol for the same reason `SwitcherSurface` is: a real tap
/// needs a login session and a permission grant, which a test process has no
/// business asking for.
///
/// Every operation has to be safe with no tap in hand. The recovery that asks
/// `isEnabled` on a loop is stopped after `invalidate()` rather than before,
/// so one ask can run against a tap that is already gone. Answering that
/// safely is cheaper than ordering the teardown around it, and it keeps the
/// requirement here, where an implementation can be held to it, rather than in
/// a caller that could forget.
@MainActor
protocol EventTapControlling {
    /// Whether the system says this process may listen to events. Advisory
    /// only — `start` is the one that decides.
    var hasPermission: Bool { get }

    /// Whether the tap exists and is currently enabled.
    var isEnabled: Bool { get }

    /// Creates the tap, puts it on the current run loop and enables it.
    /// `false` means there is no tap that will deliver events — none was
    /// made, none could be put on a run loop, or the one that was made is not
    /// enabled — and is the only thing the fallback is decided on.
    func start(
        onCommandRelease: @escaping @MainActor () -> Void,
        onDisabledBySystem: @escaping @MainActor () -> Void
    ) -> Bool

    /// Turns a disabled tap back on. `false` when it could not be.
    func enable() -> Bool

    /// Turns the tap off without destroying it. `false` when it did not go
    /// down — there was no tap to switch off, or the request was not honoured.
    ///
    /// Silent towards the system: a stop asked for here sends no notice, not
    /// even to the process that asked. That is the point of it — it stages the
    /// kind of stop only the loop asking `isEnabled` can find, so the route
    /// that does not depend on being told can be watched working.
    ///
    /// Reporting back is no contradiction of that silence. What comes back is
    /// this call's own account to the caller that made it, which travels
    /// through no notification and reaches nothing else. Switching a tap off
    /// is a request exactly as starting and enabling are, and the one request
    /// here that said nothing about how it went was the odd one out: a caller
    /// that announced a stop it had not been told had happened would be
    /// describing its intention rather than the machine.
    func disable() -> Bool

    /// Takes the tap down for good.
    func invalidate()
}

/// The real tap: a listen-only subscription to modifier-key changes across
/// the session.
///
/// A class rather than a value for the same reason `HotkeyManager` is one:
/// Core Graphics is handed a raw pointer to the owner and hands it back on
/// every event, so something has to stay at that address for as long as the
/// tap is installed.
@MainActor
final class SystemEventTap: EventTapControlling {
    /// The whole session's events, which is the only choice that sees other
    /// applications' modifier keys while this process sits inactive.
    /// `.cghidEventTap` demands root and `.cgAnnotatedSessionEventTap` sees
    /// only events addressed to this process.
    private static let location = CGEventTapLocation.cgSessionEventTap

    /// At the head, so this tap still observes events that a tap ahead of it
    /// would otherwise consume.
    private static let placement = CGEventTapPlacement.headInsertEventTap

    /// This value *is* the promise that nothing here delays or swallows a
    /// keystroke. A listen-only tap cannot alter or drop an event — the return
    /// value of its callback is ignored by the system. Change it to
    /// `.defaultTap` and "does not interfere with delivery" drops from a
    /// property of the API to a rule the implementation has to keep
    /// remembering.
    private static let options = CGEventTapOptions.listenOnly

    /// This value *is* the promise that nothing typed is ever read. Characters
    /// are not delivered to this tap at all, because nothing but
    /// `.flagsChanged` is subscribed. Widen the mask and "never reads what is
    /// typed" drops from a property of the API to a rule the implementation
    /// has to keep remembering.
    private static let eventsOfInterest: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onCommandRelease: (@MainActor () -> Void)?
    private var onDisabledBySystem: (@MainActor () -> Void)?

    /// The modifier state as of the last change seen, which is the other half
    /// of the falling-edge test below. Seeded from the system rather than
    /// started empty, so a Command already held when the tap goes up is known
    /// about and its release is not missed.
    private var previousFlags: CGEventFlags = []

    /// Read for the wording of one diagnostics line and nothing else.
    ///
    /// `start` is the single source of truth about whether there is a tap:
    /// this answers "would the system say yes", and only `tapCreate` answers
    /// "did it". Keeping the decision on the return value is what absorbs the
    /// open question of which grant a tap actually needs — there are reports
    /// that Accessibility alone suffices, and nothing official either way. If
    /// those reports are right, this returns false while the tap is made all
    /// the same, and the only thing that would have been wrong is a sentence
    /// telling the user where to look.
    var hasPermission: Bool {
        CGPreflightListenEventAccess()
    }

    var isEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Whether this change is Command being let go, rather than some other
    /// modifier moving while Command was already up.
    ///
    /// The falling edge, not the state: a `.flagsChanged` without
    /// `.maskCommand` is either Command coming up or Shift moving with
    /// Command already up, and only the first is a commit. Reading
    /// `current` alone conflates them, which shows up while a panel is
    /// stranded with Command not held — the state a stopped monitor leaves
    /// behind. There, one tap of Shift would commit a selection the user
    /// never confirmed.
    ///
    /// `.maskCommand` stays set while either Command is down, so swapping
    /// hands never produces this edge and needs no case of its own. Nor does
    /// letting go of Shift, Option or Control: none of them move this bit.
    /// The left and right Command keys are not told apart. The device-
    /// dependent bits that would tell them apart ride on the same flags, and
    /// this feature has no use for the distinction.
    ///
    /// Takes flags rather than the event so that a test can ask the question
    /// without building a `CGEvent` — this sits below `EventTapControlling`,
    /// where `FakeEventTap` cannot reach it.
    ///
    /// `nonisolated` says the rest of it: two values in, a `Bool` out, and
    /// nothing of the actor's touched in between. Without it the judgement
    /// would inherit the type's isolation and a test could only ask it from
    /// the main actor, which would suggest the answer depended on where it
    /// was asked from.
    nonisolated static func shouldReportRelease(
        previous: CGEventFlags,
        current: CGEventFlags
    ) -> Bool {
        previous.contains(.maskCommand) && !current.contains(.maskCommand)
    }

    func start(
        onCommandRelease: @escaping @MainActor () -> Void,
        onDisabledBySystem: @escaping @MainActor () -> Void
    ) -> Bool {
        guard let tap = CGEvent.tapCreate(
            tap: Self.location,
            place: Self.placement,
            options: Self.options,
            eventsOfInterest: Self.eventsOfInterest,
            callback: handleModifierEvent,
            // The other end of the `fromOpaque` in the callback. A
            // `@convention(c)` function captures nothing, so this pointer is
            // the only channel there is.
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        self.onCommandRelease = onCommandRelease
        self.onDisabledBySystem = onDisabledBySystem

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            // Read like the enabling below, and for the same reason: making a
            // source is a request too, and a request can be turned down. It is
            // imported as returning an implicitly unwrapped optional, so a
            // refusal would otherwise travel on as a NULL nobody stopped,
            // leaving a tap on no run loop at all — enabled, answering yes to
            // every question asked of it, and delivering nothing for as long as
            // the app runs.
            //
            // Everything already put on `self` comes back off before the
            // answer, rather than being left for the caller to notice. `false`
            // has to mean there is no monitor: a tap left behind here would be
            // found by `enable()` and switched back on, still attached to
            // nothing, and `isEnabled` would agree with it.
            invalidate()
            return false
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        seedPreviousFlags()
        CGEvent.tapEnable(tap: tap, enable: true)
        // Read back rather than assumed. The fallback is decided on this one
        // Bool, so it has to mean "this tap will deliver events" and not "a
        // tap object exists" — enabling is a request, and a request can be
        // turned down. `enable()` answers the same question the same way.
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func enable() -> Bool {
        guard let tap else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        // Sown again, not carried over. Nothing was delivered while the tap
        // was off, so the held value describes a keyboard that has since
        // moved on; carrying it over would either miss the next release or
        // invent one.
        seedPreviousFlags()
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func disable() -> Bool {
        guard let tap else { return false }
        CGEvent.tapEnable(tap: tap, enable: false)
        // Read back rather than assumed, for the reason `enable()` reads back
        // and `start()` before it: switching a tap off is a request too, and
        // `tapEnable` reports nothing about whether this one was granted. A
        // caller told it had stopped a tap that is still delivering would go
        // on to describe a stop that never happened.
        return !CGEvent.tapIsEnabled(tap: tap)
    }

    func invalidate() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        onCommandRelease = nil
        onDisabledBySystem = nil
    }

    /// Takes the modifier state as the system has it now.
    private func seedPreviousFlags() {
        previousFlags = CGEventSource.flagsState(.combinedSessionState)
    }

    /// The only place the held flags and the stored closures are touched, so
    /// the callback above can stay a translation from a C pointer to a call.
    ///
    /// Takes `CGEventFlags` rather than the `CGEvent` so the event's lifetime
    /// never outlives the callback that was handed it.
    fileprivate func receive(type: CGEventType, flags: CGEventFlags) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // These arrive whatever the mask says. Acting on them is what
            // makes the zero-delay half of the recovery work.
            onDisabledBySystem?()
        case .flagsChanged:
            let released = Self.shouldReportRelease(previous: previousFlags, current: flags)
            previousFlags = flags
            if released {
                onCommandRelease?()
            }
        default:
            break
        }
    }
}

/// Core Graphics' callback for a modifier change.
///
/// A `@convention(c)` function captures nothing, so the tap arrives through
/// `userInfo`; that pointer is the only channel there is. The same two-step
/// shape as `HotkeyManager`'s handler, and for the same reason: Swift 6 will
/// not let a non-isolated C callback call a `@MainActor` closure
/// synchronously, and the run-time fact that the tap sits on the main run
/// loop is not something the compiler can be shown.
private func handleModifierEvent(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Listen-only taps have their return value ignored, but the event still
    // has to come back unretained so its lifetime is not cut short.
    guard let userInfo else {
        // `start` is the only caller and it always passes the pointer, so
        // nothing reaches here. It says so all the same rather than slipping
        // away quietly, because a return with nothing written would read
        // exactly like a tap that was never sent an event at all.
        Diagnostics.writeLine("event ignored; the callback arrived with no way back to the tap")
        return Unmanaged.passUnretained(event)
    }
    let tap = Unmanaged<SystemEventTap>.fromOpaque(userInfo).takeUnretainedValue()

    guard Thread.isMainThread else {
        // The tap is on the main run loop, so this should not happen; it was
        // measured not happening, 48 events out of 48. Say so rather than
        // dropping it in silence: a disable notice lost here would look
        // exactly like a tap that never went down, and the type is the only
        // thing in the line that tells those two apart.
        Diagnostics.writeLine(
            "modifier monitor callback ran off the main thread; event ignored "
                + "(type \(type.rawValue))"
        )
        return Unmanaged.passUnretained(event)
    }
    // Read out here rather than inside the hop. `CGEvent` is not `Sendable`,
    // so handing the event itself across is a compile error — and it is the
    // right error: the event's lifetime ends with this call, while the flags
    // are a plain value that can outlive it.
    let flags = event.flags
    MainActor.assumeIsolated { tap.receive(type: type, flags: flags) }
    return Unmanaged.passUnretained(event)
}
