import Carbon.HIToolbox
import Foundation
import Logging

/// Stamped on every hotkey this app registers, spelling "LTRN". A press
/// carrying anything else belongs to some other handler on the same target and
/// is left alone.
private let hotkeySignature: OSType = 0x4C54_524E

// MARK: - HotkeyRegistrationOutcome

/// What one round of hotkey registration achieved.
///
/// The two combinations are registered separately and either can fail on its
/// own, so the result is a pair of lists rather than a yes or no. This is also
/// the only place the launch diagnostics line is worded, which keeps the shape
/// of that line testable while the registration itself is not.
struct HotkeyRegistrationOutcome: Sendable {

  // MARK: Lifecycle

  /// `assert` rather than `precondition`: a combination on both lists, or
  /// on neither, is loud in debug builds and under test, but a misworded
  /// line must never take the app down in release — an app that cannot
  /// claim its hotkeys is the very thing this line exists to report.
  init(
    registered: [HotkeyCombination],
    failures: [Failure],
    displayNames: [HotkeyCombination: String] = [:]
  ) {
    // Two clauses because each catches a case the other passes: a
    // duplicate standing in for a missing combination keeps the count
    // right and is caught only by the set, while a duplicate on top of
    // full coverage keeps the set whole and is caught only by the count.
    // A plain omission trips both.
    let accounted = registered + failures.map(\.combination)
    assert(
      Set(accounted) == Set(HotkeyCombination.all)
        && accounted.count == HotkeyCombination.all.count,
      "every combination must be registered or failed, exactly once"
    )
    self.registered = registered
    self.failures = failures
    self.displayNames = displayNames
  }

  // MARK: Internal

  /// A combination the system would not hand over, and the status it gave.
  struct Failure: Sendable {
    init(combination: HotkeyCombination, status: OSStatus, displayName: String? = nil) {
      self.combination = combination
      self.status = status
      self.displayName = displayName
    }

    let combination: HotkeyCombination
    let status: OSStatus
    /// How the line names it, when the registered key is not the
    /// long-standing one. Absent means the combination's own name.
    let displayName: String?
  }

  let registered: [HotkeyCombination]
  let failures: [Failure]
  /// How the line names a taken combination, when its keys are not
  /// the long-standing ones. Combinations absent here keep their own
  /// names, so outcomes built without custom keys read exactly as
  /// before.
  let displayNames: [HotkeyCombination: String]

  /// Nothing was registered, so there is no way left to reach the switcher
  /// and no reason to stay running.
  var isTotalFailure: Bool {
    registered.isEmpty
  }

  /// The level the one launch line carries: silence when everything
  /// registered, a warning when some did not, an error when none did
  /// and the run ends here.
  var logLevel: Logger.Level {
    isTotalFailure ? .error : (failures.isEmpty ? .info : .warning)
  }

  /// The one line written after registration: what was taken, what was not
  /// and why, and whether that leaves anything to run for.
  var summaryLine: String {
    var segments = [String]()
    if !registered.isEmpty {
      segments.append(
        "registered "
          + registered.lazy.map { displayNames[$0] ?? $0.name }.joined(separator: ", ")
      )
    }
    if !failures.isEmpty {
      let reasons = failures.map { failure in
        let name = failure.displayName ?? failure.combination.name
        if failure.status == noErr {
          return "\(name) (no key is bound)"
        }
        return "\(name) (error \(failure.status))"
      }
      segments.append("could not register " + reasons.joined(separator: ", "))
    }
    if isTotalFailure {
      segments.append("no hotkey registered, exiting")
    }
    return segments.joined(separator: "; ")
  }

}

// MARK: - HotkeyManager

/// Holds the switcher's hotkeys with Carbon and turns a press into a call.
///
/// A class rather than a value: Carbon is handed a raw pointer to the owner
/// and hands it back on every press, so something has to stay at that address
/// for as long as the handler is installed.
@MainActor
final class HotkeyManager {

  // MARK: Lifecycle

  init(onPress: @escaping @MainActor (HotkeyCombination, Duration?) -> Void) {
    self.onPress = onPress
  }

  // MARK: Internal

  /// Refused keys whose combination still registered on other keys.
  /// Fully refused combinations read on the outcome line itself, so
  /// only the partial ones need a line of their own. The caller writes
  /// them; this manager never touches diagnostics.
  private(set) var refusedDetails = [String]()

  /// Installs the handler and claims the given bindings.
  ///
  /// Called once at launch with the resolved invocation keys. Each
  /// combination lands taken when at least one of its keys was handed
  /// over, and refused only when none was: a half-working invocation
  /// still opens the switcher. An invocation with no keys at all is
  /// refused without asking, so the line says what is missing rather
  /// than printing a zero status.
  ///
  /// The answer is remembered: a second call reports what the first
  /// achieved rather than attempting any of it again, because Carbon would
  /// either refuse the combinations this manager is still holding — which
  /// reads as a total failure — or accept them a second time and fire
  /// `onPress` twice for one press. `unregister()` is what lets a later
  /// call start over.
  func register(bindings: [HotkeyBinding] = HotkeyBinding.defaults) -> HotkeyRegistrationOutcome {
    if let registrationOutcome {
      return registrationOutcome
    }

    if let status = installHandler() {
      // A hotkey with no handler behind it would swallow the press and
      // do nothing with it, which is worse than not claiming it, so none
      // is claimed.
      let outcome = HotkeyRegistrationOutcome(
        registered: [],
        failures: HotkeyCombination.all.map {
          HotkeyRegistrationOutcome.Failure(combination: $0, status: status)
        }
      )
      registrationOutcome = outcome
      return outcome
    }

    var taken = [HotkeyCombination: [String]]()
    var refused = [HotkeyCombination: [(name: String, status: OSStatus)]]()
    for binding in bindings {
      attempt(binding, taken: &taken, refused: &refused)
    }
    let outcome = assembleOutcome(taken: taken, refused: refused)
    registrationOutcome = outcome
    return outcome
  }

  /// Gives every claimed combination back, takes the handler down and
  /// forgets the outcome, which is one job in three parts: a manager that
  /// had given the combinations back but still remembered an outcome would
  /// refuse to claim them again.
  func unregister() {
    for reference in hotKeys {
      UnregisterEventHotKey(reference)
    }
    hotKeys.removeAll()
    refusedDetails = []
    if let eventHandler {
      RemoveEventHandler(eventHandler)
      self.eventHandler = nil
    }
    registrationOutcome = nil
  }

  // MARK: Fileprivate

  /// Called for each press, with the combination and how long the press took
  /// to reach this process.
  ///
  /// `fileprivate` because the C callback below is a free function — it
  /// cannot be a method, having nowhere to keep a `self` — and free
  /// functions are outside a `private` member's reach.
  fileprivate let onPress: @MainActor (HotkeyCombination, Duration?) -> Void

  // MARK: Private

  private var eventHandler: EventHandlerRef?
  /// Only the ones that were actually taken.
  private var hotKeys = [EventHotKeyRef]()
  /// What the first `register()` achieved. Present from that call until
  /// `unregister()`, and the reason a repeat call need attempt nothing.
  private var registrationOutcome: HotkeyRegistrationOutcome?

  /// Attempts one binding, keeping the take or the refusal.
  private func attempt(
    _ binding: HotkeyBinding,
    taken: inout [HotkeyCombination: [String]],
    refused: inout [HotkeyCombination: [(name: String, status: OSStatus)]]
  ) {
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      binding.keyCode,
      binding.carbonModifiers,
      EventHotKeyID(signature: hotkeySignature, id: binding.eventID),
      GetEventDispatcherTarget(),
      // Shared rather than exclusive, and not as a preference.
      // Asking exclusively was tried: it came back
      // `eventHotKeyExistsErr` for every combination, so exclusive
      // is not a stricter form of this call but one that never
      // hands back a hotkey at all. Something already holds them
      // when this runs, and the system's own assignment is the one
      // thing known to — it is switched off only after this loop
      // has succeeded. Shared is also what lets this app run
      // alongside another switcher, with both answering.
      OptionBits(kEventHotKeyNoOptions),
      &reference
    )
    if status == noErr, let reference {
      hotKeys.append(reference)
      taken[binding.combination, default: []].append(binding.name)
    } else {
      refused[binding.combination, default: []].append((binding.name, status))
    }
  }

  /// Folds takes and refusals into the combination-level outcome.
  ///
  /// Partial refusals get their own lines on the side: the outcome
  /// only has room for one status per combination.
  private func assembleOutcome(
    taken: [HotkeyCombination: [String]],
    refused: [HotkeyCombination: [(name: String, status: OSStatus)]]
  ) -> HotkeyRegistrationOutcome {
    var registered = [HotkeyCombination]()
    var failures = [HotkeyRegistrationOutcome.Failure]()
    var displayNames = [HotkeyCombination: String]()
    for combination in HotkeyCombination.all {
      if let names = taken[combination], !names.isEmpty {
        registered.append(combination)
        displayNames[combination] = names.joined(separator: ", ")
        for refusal in refused[combination] ?? [] {
          refusedDetails.append("could not register \(refusal.name) (error \(refusal.status))")
        }
      } else if let refusals = refused[combination], let first = refusals.first {
        failures.append(HotkeyRegistrationOutcome.Failure(
          combination: combination,
          status: first.status,
          displayName: refusals.map(\.name).joined(separator: ", ")
        ))
      } else {
        failures.append(HotkeyRegistrationOutcome.Failure(
          combination: combination,
          status: noErr,
          displayName: combination.name
        ))
      }
    }
    return HotkeyRegistrationOutcome(
      registered: registered,
      failures: failures,
      displayNames: displayNames
    )
  }

  /// Installs the one handler both hotkeys report to, and returns `nil`
  /// having done so, or the status saying why it could not. Keeping a
  /// second `register()` from stacking handlers is `register()`'s job now,
  /// so this is only ever reached with nothing installed.
  private func installHandler() -> OSStatus? {
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
  guard
    read == noErr,
    identifier.signature == hotkeySignature,
    GetEventKind(event) == UInt32(kEventHotKeyPressed),
    let combination = HotkeyBinding.combination(forEventID: identifier.id)
  else {
    return OSStatus(eventNotHandledErr)
  }

  // Read before the press is acted on, so the figure covers the system's
  // delivery of it and none of the work that follows. Both readings are
  // seconds since boot on the same clock, so the subtraction stands on its
  // own with no conversion in between.
  let delay = Duration.seconds(GetCurrentEventTime() - GetEventTime(event))

  // The other end of the `passUnretained` in `installHandler()`: where the
  // pointer becomes the manager again.
  let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

  // Carbon does not promise which thread runs a handler. The dispatcher
  // target runs it on whichever thread pumps the event loop, which under a
  // running application is the main one, but the guard is what makes the
  // assumption below sound rather than hopeful. It answers with a line and
  // a refusal rather than a trap: a crash here would leave the process
  // dead with the system's Cmd+Tab still disabled, the very failure the
  // shutdown path exists to prevent. The drop is written down because with
  // that switcher off, an unrecorded one is a key that does nothing for no
  // visible reason.
  guard Thread.isMainThread else {
    Diagnostics.writeLine(LogLine(
      .warning,
      .hotkey,
      "dropped \(combination.name); Carbon ran the handler off the main thread"
    ))
    return OSStatus(eventNotHandledErr)
  }
  MainActor.assumeIsolated {
    manager.onPress(combination, delay)
  }
  return noErr
}
