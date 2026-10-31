import ApplicationServices
import CoreGraphics
import Foundation
import os
import Synchronization

// MARK: - FastSearchGateBox

/// The gate and the conditions it reads, shared by the tap's thread and the
/// main actor.
///
/// The tap's thread asks about every key event and must never wait on the
/// main actor, so the two meet here behind locks rather than through it.
/// The main actor only replaces the conditions and tells the gate a panel
/// closed or a search stood down.
final class FastSearchGateBox: Sendable {

  // MARK: Internal

  /// Whether a search is running, for the release watch.
  var isRunning: Bool {
    gate.withLock { $0.isRunning }
  }

  /// Whether the next decision needs Escape's live state.
  var waitsOnEscape: Bool {
    gate.withLock { $0.waitsOnEscape }
  }

  func decide(_ event: FastSearchEvent) -> (verdict: FastSearchVerdict, effect: FastSearchEffect?) {
    let current = conditions.withLock { $0 }
    return gate.withLock { $0.handle(event, conditions: current) }
  }

  func updateConditions(_ change: (inout FastSearchConditions) -> Void) {
    conditions.withLock { change(&$0) }
  }

  func tapDisabled() -> FastSearchEffect? {
    gate.withLock { $0.tapDisabled() }
  }

  func panelClosed() {
    gate.withLock { $0.panelClosed() }
  }

  func standDown() {
    gate.withLock { $0.standDown() }
  }

  /// Starts over as waiting, for a tap made afresh.
  func reset() {
    gate.withLock { $0 = FastSearchGate() }
  }

  // MARK: Private

  private let gate = Mutex(FastSearchGate())
  private let conditions = Mutex(FastSearchConditions())

}

// MARK: - FastSearchTapControlling

/// The operations on the Fast Search tap that its owner needs.
///
/// Behind a protocol for the reason `EventTapControlling` is: a real tap
/// needs a login session and a permission grant a test process has no
/// business asking for.
@MainActor
protocol FastSearchTapControlling: AnyObject {
  /// Whether the system says this process is trusted for accessibility.
  /// Read only to word the line when the tap cannot be made.
  var accessibilityGranted: Bool { get }

  /// Whether the tap exists and is enabled.
  var isEnabled: Bool { get }

  /// Makes the tap on its own thread and enables it. `false` means no tap
  /// will see a key, and nothing has been left behind.
  func start(
    box: FastSearchGateBox,
    onEffect: @escaping @MainActor (FastSearchEffect) -> Void,
    onDisabledBySystem: @escaping @MainActor (_ reenabled: Bool) -> Void
  ) -> Bool

  /// Turns a disabled tap back on. `false` when it could not be.
  func enable() -> Bool

  /// Takes the tap down and ends its thread.
  func stop()
}

// MARK: - SystemFastSearchTap

/// The real tap: an active subscription to key presses, releases and
/// modifier changes, on a thread of its own.
///
/// Active, unlike the modifier monitor's, because a search keeps its
/// letters from the front application, which only a tap that may drop
/// events can do. On its own thread because the system waits for an active
/// tap's answer before delivering each key to any application: answered on
/// the main thread, every keystroke in the session would wait whenever the
/// main thread is busy taking a window, and the system would switch the
/// tap off. Exists only while a Fast Search modifier is enabled, so with
/// none enabled no keystroke passes through anything of this app's.
@MainActor
final class SystemFastSearchTap: FastSearchTapControlling {

  // MARK: Internal

  var accessibilityGranted: Bool {
    AXIsProcessTrusted()
  }

  var isEnabled: Bool {
    context?.isEnabled ?? false
  }

  func start(
    box: FastSearchGateBox,
    onEffect: @escaping @MainActor (FastSearchEffect) -> Void,
    onDisabledBySystem: @escaping @MainActor (_ reenabled: Bool) -> Void
  ) -> Bool {
    stop()
    let context = TapContext(box: box, onEffect: onEffect, onDisabledBySystem: onDisabledBySystem)
    guard context.run() else { return false }
    self.context = context
    return true
  }

  func enable() -> Bool {
    context?.enable() ?? false
  }

  func stop() {
    context?.end()
    context = nil
  }

  // MARK: Private

  private var context: TapContext?

}

// MARK: - TapContext

/// What the tap's thread holds: the tap, its run loop, and the way back to
/// the main actor. Reached from the C callback through a raw pointer, so it
/// stays alive at one address for as long as the tap is installed.
// swiftlint:disable:next no_unchecked_sendable - Every mutable state below is guarded by the lock
private final class TapContext: @unchecked Sendable {

  // MARK: Lifecycle

  init(
    box: FastSearchGateBox,
    onEffect: @escaping @MainActor (FastSearchEffect) -> Void,
    onDisabledBySystem: @escaping @MainActor (Bool) -> Void
  ) {
    self.box = box
    self.onEffect = onEffect
    self.onDisabledBySystem = onDisabledBySystem
  }

  // MARK: Internal

  /// Marks the Escape this tap sends itself, so it passes untouched.
  static let marker: Int64 = 0x4C4E_5445

  let box: FastSearchGateBox

  var isEnabled: Bool {
    withState { $0.tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
  }

  /// Starts the thread and waits for it to say whether the tap is up.
  func run() -> Bool {
    let ready = DispatchSemaphore(value: 0)
    let made = Mutex(false)
    let thread = Thread { [self] in
      let loop = CFRunLoopGetCurrent()
      guard let (tap, source) = makeTap() else {
        ready.signal()
        return
      }
      CFRunLoopAddSource(loop, source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
      let enabled = CGEvent.tapIsEnabled(tap: tap)
      withState { $0 = TapState(tap: tap, source: source, loop: loop) }
      made.withLock { $0 = enabled }
      ready.signal()
      guard enabled else { return }
      CFRunLoopRun()
    }
    thread.name = "Fast Search tap"
    thread.qualityOfService = .userInteractive
    thread.start()
    ready.wait()
    let enabled = made.withLock { $0 }
    if !enabled {
      end()
    }
    return enabled
  }

  func enable() -> Bool {
    withState { held in
      guard let tap = held.tap else { return false }
      CGEvent.tapEnable(tap: tap, enable: true)
      return CGEvent.tapIsEnabled(tap: tap)
    }
  }

  func end() {
    let held = withState { held in
      defer { held = TapState() }
      return held
    }
    if let tap = held.tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
    }
    if let loop = held.loop {
      CFRunLoopStop(loop)
    }
  }

  /// Decides one event on the tap's thread.
  func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let passed = Unmanaged.passUnretained(event)
    switch type {
    case .tapDisabledByTimeout,
         .tapDisabledByUserInput:
      let reenabled = enable()
      let effect = box.tapDisabled()
      deliver { [onDisabledBySystem, onEffect] in
        if let effect {
          onEffect(effect)
        }
        onDisabledBySystem(reenabled)
      }
      return passed

    case .keyDown,
         .keyUp,
         .flagsChanged:
      break

    default:
      return passed
    }
    guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return passed }

    let signpost = Self.signposter.beginInterval("decide")
    let reading = read(event, type: type)
    let (verdict, effect) = box.decide(reading)
    Self.signposter.endInterval("decide", signpost)

    if verdict.injectsEscape {
      injectEscape(proxy)
    }
    if let effect {
      deliver { [onEffect] in onEffect(effect) }
    }
    return verdict.swallows ? nil : passed
  }

  // MARK: Private

  private struct TapState {
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var loop: CFRunLoop?
  }

  private static let signposter = OSSignposter(
    subsystem: Bundle.main.bundleIdentifier ?? "Lanterna",
    category: "fast search"
  )

  private static let escapeKeyCode: UInt16 = 53

  private let onEffect: @MainActor (FastSearchEffect) -> Void
  private let onDisabledBySystem: @MainActor (Bool) -> Void
  /// The tap and its run loop, reached from the tap's thread and the main
  /// actor. A plain lock rather than `Mutex`: the Core Foundation objects
  /// are not `Sendable`, and this class already vouches for their use.
  private let lock = NSLock()
  private var state = TapState()

  /// How long the event took to get here. The event's stamp counts on the
  /// clock that stops while the machine sleeps, so it is compared with that
  /// clock rather than with one that runs through sleep.
  private static func deliveryDelay(of event: CGEvent) -> Duration? {
    let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    guard now >= event.timestamp else { return nil }
    return .nanoseconds(Int64(now - event.timestamp))
  }

  private static func text(of event: CGEvent) -> String {
    var length = 0
    var buffer = [UniChar](repeating: 0, count: 4)
    event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
    return String(utf16CodeUnits: buffer, count: length)
  }

  private func withState<Result>(_ body: (inout TapState) -> Result) -> Result {
    lock.lock()
    defer { lock.unlock() }
    return body(&state)
  }

  private func makeTap() -> (CFMachPort, CFRunLoopSource)? {
    let mask: CGEventMask =
      (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.keyUp.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: handleFastSearchEvent,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      return nil
    }
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      CFMachPortInvalidate(tap)
      return nil
    }
    return (tap, source)
  }

  /// Reads what the gate needs off the event, and nothing it does not.
  private func read(_ event: CGEvent, type: CGEventType) -> FastSearchEvent {
    let kind: FastSearchEvent.Kind =
      switch type {
      case .keyDown: .keyDown
      case .keyUp: .keyUp
      default: .flagsChanged
      }
    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    var reading = FastSearchEvent(
      kind: kind,
      keyCode: keyCode,
      flags: event.flags,
      isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
      characters: kind == .keyDown ? Self.text(of: event) : "",
      receivedAt: .now,
      deliveryDelay: Self.deliveryDelay(of: event)
    )
    // Escape's own press and release are answered by the gate's rows for
    // them; reading the state for those too would let one release count twice.
    if keyCode != Self.escapeKeyCode || kind == .flagsChanged, box.waitsOnEscape {
      reading.escapeDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(Self.escapeKeyCode))
    }
    return reading
  }

  /// Sends the held-back Escape ahead of the event being answered.
  ///
  /// Made from a private source with no flags, so a Command held at the time
  /// does not turn it into Command-Escape on the way to the application.
  private func injectEscape(_ proxy: CGEventTapProxy) {
    let source = CGEventSource(stateID: .privateState)
    for keyDown in [true, false] {
      guard
        let escape = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(Self.escapeKeyCode), keyDown: keyDown)
      else {
        continue
      }
      escape.flags = []
      escape.setIntegerValueField(.eventSourceUserData, value: Self.marker)
      escape.tapPostEvent(proxy)
    }
  }

  /// Hands work to the main actor in the order events arrived.
  private func deliver(_ work: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async {
      MainActor.assumeIsolated { work() }
    }
  }

}

/// Core Graphics' callback for the Fast Search tap, on the tap's thread.
private func handleFastSearchEvent(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  return Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue().handle(proxy: proxy, type: type, event: event)
}
