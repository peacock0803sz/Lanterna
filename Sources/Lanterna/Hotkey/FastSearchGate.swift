import AppKit
import CoreGraphics

// MARK: - FastSearchConditions

/// What the main actor tells the tap's thread. Changed in place under a
/// lock; each decision reads a copy.
struct FastSearchConditions: Equatable, Sendable {
  /// The modifiers the user turned on.
  var enabled = Set<FastSearchModifier>()
  /// Whether a search may start now: no switcher panel is up or on its way,
  /// and no key binding is being recorded.
  var canStart = false
  /// How key codes read as letters under the current layout.
  var characters = KeyCharacterTable.empty
}

// MARK: - FastSearchEvent

/// One keyboard event as the tap read it, with nothing of the event kept.
struct FastSearchEvent: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case keyDown
    case keyUp
    case flagsChanged
  }

  var kind: Kind
  var keyCode: UInt16
  var flags: CGEventFlags
  var isRepeat = false
  /// The text the event itself carries, every modifier applied.
  var characters = ""
  var receivedAt = ContinuousClock.now
  /// How long the event took to reach the tap, when that could be read.
  var deliveryDelay: Duration?
  /// Whether Escape is still down, read by the tap just before asking.
  /// Nil when it was not read; only the Caps Lock states need it.
  var escapeDown: Bool?
}

// MARK: - FastSearchVerdict

/// What the tap does with the event it asked about.
enum FastSearchVerdict: Equatable, Sendable {
  case pass
  case swallow
  /// Sends a held-back Escape press and release first, then the event.
  case injectEscapeThenPass
  /// Sends a held-back Escape press and release in place of the event.
  case injectEscapeThenSwallow

  var swallows: Bool {
    self == .swallow || self == .injectEscapeThenSwallow
  }

  var injectsEscape: Bool {
    self == .injectEscapeThenPass || self == .injectEscapeThenSwallow
  }
}

// MARK: - FastSearchMove

enum FastSearchMove: Equatable, Sendable {
  case next
  case previous
}

// MARK: - FastSearchEffect

/// What the main actor is told, in the order the events arrived.
enum FastSearchEffect: Equatable, Sendable {
  /// The first letter. The search starts with it.
  case begin(PanelKeystroke, modifier: FastSearchModifier, receivedAt: ContinuousClock.Instant, deliveryDelay: Duration?)
  /// A later press, already rewritten for the panel.
  case keystroke(PanelKeystroke)
  /// Tab with the starting key: moves the selection.
  case move(FastSearchMove)
  /// The starting key came up.
  case release(FastSearchModifier, receivedAt: ContinuousClock.Instant)
  /// The system stopped the tap during a search.
  case interrupted
}

// MARK: - FastSearchGate

/// Decides, for each keyboard event, whether Fast Search takes it.
///
/// A value so that every row of the decision can be put through a test
/// without a tap, and so that the tap's thread and the main actor can share
/// it behind one lock. Asked on the tap's thread for every key event while
/// any modifier is enabled, so nothing here touches the main actor.
///
/// Once a search starts, every press and its release are kept from the
/// front application until the starting key comes up, so no letter of the
/// query lands in the document the user is leaving.
struct FastSearchGate: Equatable, Sendable {

  // MARK: Internal

  enum State: Equatable, Sendable {
    /// Waiting.
    case idle
    /// Escape went down with Caps Lock enabled and is held back, to learn
    /// whether a letter follows.
    case escapeHeld
    /// The held-back Escape was sent on. Nothing starts until it comes up.
    case escapeSpent
    /// The press went to the system or another panel. Everything passes
    /// until the key comes up.
    case passedThrough(FastSearchModifier)
    /// A search is running.
    case running(Run)
    /// The search's panel closed with the key still held. Letters typed
    /// with it are dropped until it comes up.
    case awaitingRelease(Run)
  }

  /// What a running search holds.
  struct Run: Equatable, Sendable {
    let modifier: FastSearchModifier
    /// The table the search started with. A layout change mid-search
    /// does not change how its letters read.
    let characters: KeyCharacterTable
    /// The presses kept from the application, whose releases are kept too.
    var swallowed = Set<UInt16>()
  }

  private(set) var state = State.idle

  /// Whether a search is running, for the release watch.
  var isRunning: Bool {
    if case .running = state {
      return true
    }
    return false
  }

  /// Decides one event.
  mutating func handle(
    _ event: FastSearchEvent,
    conditions: FastSearchConditions
  ) -> (verdict: FastSearchVerdict, effect: FastSearchEffect?) {
    if let reset = missedRelease(event) {
      state = .idle
      let (verdict, effect) = handleIdle(event, conditions: conditions)
      if reset == .injectEscape {
        return (verdict.swallows ? .injectEscapeThenSwallow : .injectEscapeThenPass, effect)
      }
      return (verdict, effect)
    }
    switch state {
    case .idle:
      return handleIdle(event, conditions: conditions)

    case .escapeHeld:
      return handleEscapeHeld(event, conditions: conditions)

    case .escapeSpent:
      return (handleEscapeSpent(event), nil)

    case .passedThrough(let modifier):
      if isRelease(of: modifier, event) {
        state = .idle
      }
      return (.pass, nil)

    case .running(let run):
      return handleRunning(event, run: run)

    case .awaitingRelease(let run):
      return (handleAwaitingRelease(event, run: run), nil)
    }
  }

  /// The system stopped the tap. A running search cannot know whether its
  /// key came up meanwhile, so it ends; every other state is kept.
  mutating func tapDisabled() -> FastSearchEffect? {
    guard case .running(let run) = state else { return nil }
    state = .awaitingRelease(run)
    return .interrupted
  }

  /// The search's panel closed while the key may still be held.
  mutating func panelClosed() {
    guard case .running(let run) = state else { return }
    state = .awaitingRelease(run)
  }

  /// The first letter met a panel that was already up, so the search
  /// stands down and the rest of the press belongs to that panel.
  mutating func standDown() {
    guard case .running(let run) = state else { return }
    state = .passedThrough(run.modifier)
  }

  // MARK: Private

  private enum Reset {
    case plain
    case injectEscape
  }

  private static let escapeKeyCode: UInt16 = 53
  private static let tabKeyCode: UInt16 = 48

  /// What Fn makes of the arrows and Delete, mapped back.
  private static let fnKeyCodes: [UInt16: UInt16] = [
    115: 123, // Home to Left
    119: 124, // End to Right
    116: 126, // Page Up to Up
    121: 125, // Page Down to Down
    117: 51, // Forward Delete to Delete
  ]

  /// The key whose own press or release says the modifier went down or up.
  private static func keyCode(of modifier: FastSearchModifier) -> UInt16 {
    switch modifier {
    case .fn: 63
    case .capsLock: escapeKeyCode
    case .leftCommand: 55
    case .rightCommand: 54
    case .leftOption: 58
    case .rightOption: 61
    }
  }

  /// Turns a press during a search into what the panel should see.
  ///
  /// A letter typed with the starting key alone becomes the bare letter,
  /// so the key does not turn it into a shortcut. What Fn makes of the
  /// arrows and Delete is mapped back to the plain keys, and Fn itself is
  /// dropped. Tab with the starting key moves the selection, since the
  /// panel binds nothing to a bare Tab. Anything else keeps its modifiers,
  /// so Command-Period still cancels.
  private static func rewrite(_ event: FastSearchEvent, run: Run) -> FastSearchEffect {
    let shift = event.flags.contains(.maskShift)
    var flags = event.flags
    var keyCode = event.keyCode
    if run.modifier == .fn {
      flags.remove(.maskSecondaryFn)
      keyCode = fnKeyCodes[keyCode] ?? keyCode
    }
    let alone = run.modifier == .fn
      ? flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty
      : FastSearchModifier.heldAlone(flags: event.flags, escapeHeld: run.modifier == .capsLock) == run.modifier
    if alone, keyCode == tabKeyCode {
      return .move(shift ? .previous : .next)
    }
    if alone, let letter = run.characters.character(keyCode: keyCode, shift: shift) {
      return .keystroke(PanelKeystroke(keyCode: keyCode, modifiers: [], isARepeat: event.isRepeat, characters: String(letter)))
    }
    return .keystroke(PanelKeystroke(
      keyCode: keyCode,
      modifiers: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)),
      isARepeat: event.isRepeat,
      characters: event.characters
    ))
  }

  /// Whether an event says a release was missed while the tap was down.
  ///
  /// Without this, a state waiting for a release would wait forever and
  /// take the next search's letters with it. The modifier is not in the
  /// flags, its key went down afresh, or for Caps Lock, Escape is no
  /// longer down. A running search is left alone: the release watch covers
  /// it, and reading it here would end a search on a stray event.
  private func missedRelease(_ event: FastSearchEvent) -> Reset? {
    let waitingFor: FastSearchModifier
    switch state {
    case .idle,
         .running:
      return nil
    case .escapeHeld,
         .escapeSpent:
      waitingFor = .capsLock
    case .passedThrough(let modifier):
      waitingFor = modifier
    case .awaitingRelease(let run):
      waitingFor = run.modifier
    }
    let reset: Reset = state == .escapeHeld ? .injectEscape : .plain
    if waitingFor == .capsLock {
      if event.keyCode == Self.escapeKeyCode, event.kind != .flagsChanged {
        // A fresh press, not a repeat, means the last release was missed.
        return event.kind == .keyDown && !event.isRepeat ? reset : nil
      }
      return event.escapeDown == false ? reset : nil
    }
    if !waitingFor.isHeld(flags: event.flags, escapeHeld: false) {
      // The release itself is handled by each state's own row.
      return isRelease(of: waitingFor, event) ? nil : reset
    }
    // The key's own flags change with its bit set is a fresh press, which
    // cannot come while the key is still held.
    if event.kind == .flagsChanged, event.keyCode == Self.keyCode(of: waitingFor) {
      return reset
    }
    return nil
  }

  private func isRelease(of modifier: FastSearchModifier, _ event: FastSearchEvent) -> Bool {
    if modifier == .capsLock {
      return event.kind == .keyUp && event.keyCode == Self.escapeKeyCode
    }
    return event.kind == .flagsChanged && !modifier.isHeld(flags: event.flags, escapeHeld: false)
  }

  private mutating func handleIdle(
    _ event: FastSearchEvent,
    conditions: FastSearchConditions
  ) -> (verdict: FastSearchVerdict, effect: FastSearchEffect?) {
    guard event.kind == .keyDown, !event.isRepeat, conditions.canStart else { return (.pass, nil) }
    if event.keyCode == Self.escapeKeyCode {
      guard
        conditions.enabled.contains(.capsLock),
        FastSearchModifier.heldAlone(flags: event.flags, escapeHeld: true) == .capsLock
      else {
        return (.pass, nil)
      }
      state = .escapeHeld
      return (.swallow, nil)
    }
    guard
      let modifier = FastSearchModifier.heldAlone(flags: event.flags, escapeHeld: false),
      conditions.enabled.contains(modifier)
    else {
      return (.pass, nil)
    }
    return start(event, modifier: modifier, characters: conditions.characters)
  }

  /// Starts a search on a letter, unless the system keeps that Fn letter.
  private mutating func start(
    _ event: FastSearchEvent,
    modifier: FastSearchModifier,
    characters: KeyCharacterTable
  ) -> (verdict: FastSearchVerdict, effect: FastSearchEffect?) {
    guard let letter = characters.character(keyCode: event.keyCode, shift: event.flags.contains(.maskShift)) else {
      return (.pass, nil)
    }
    if modifier == .fn, FnSystemShortcuts.contains(letter) {
      state = .passedThrough(.fn)
      return (.pass, nil)
    }
    let run = Run(modifier: modifier, characters: characters, swallowed: [event.keyCode])
    state = .running(run)
    let keystroke = PanelKeystroke(keyCode: event.keyCode, modifiers: [], isARepeat: false, characters: String(letter))
    return (.swallow, .begin(keystroke, modifier: modifier, receivedAt: event.receivedAt, deliveryDelay: event.deliveryDelay))
  }

  private mutating func handleEscapeHeld(
    _ event: FastSearchEvent,
    conditions: FastSearchConditions
  ) -> (verdict: FastSearchVerdict, effect: FastSearchEffect?) {
    switch event.kind {
    case .keyDown where event.keyCode == Self.escapeKeyCode:
      return (.swallow, nil)

    case .keyDown:
      if
        conditions.canStart,
        !event.isRepeat,
        FastSearchModifier.heldAlone(flags: event.flags, escapeHeld: true) == .capsLock,
        conditions.enabled.contains(.capsLock)
      {
        let started = start(event, modifier: .capsLock, characters: conditions.characters)
        if started.verdict == .swallow {
          return started
        }
      }
      state = .escapeSpent
      return (.injectEscapeThenPass, nil)

    case .keyUp where event.keyCode == Self.escapeKeyCode:
      state = .idle
      return (.injectEscapeThenSwallow, nil)

    case .flagsChanged where FastSearchModifier.heldAlone(flags: event.flags, escapeHeld: true) != .capsLock:
      // Sent before the modifier goes down, or the application would read
      // the held-back Escape as Command-Escape and the like.
      state = .escapeSpent
      return (.injectEscapeThenPass, nil)

    default:
      return (.pass, nil)
    }
  }

  private mutating func handleEscapeSpent(_ event: FastSearchEvent) -> FastSearchVerdict {
    guard event.keyCode == Self.escapeKeyCode, event.kind != .flagsChanged else { return .pass }
    if event.kind == .keyUp {
      state = .idle
    }
    return .swallow
  }

  private mutating func handleRunning(
    _ event: FastSearchEvent,
    run: Run
  ) -> (verdict: FastSearchVerdict, effect: FastSearchEffect?) {
    var run = run
    if isRelease(of: run.modifier, event) {
      state = .idle
      let verdict: FastSearchVerdict = run.modifier == .capsLock ? .swallow : .pass
      return (verdict, .release(run.modifier, receivedAt: event.receivedAt))
    }
    switch event.kind {
    case .keyDown:
      if run.modifier == .capsLock, event.keyCode == Self.escapeKeyCode {
        return (.swallow, nil)
      }
      run.swallowed.insert(event.keyCode)
      state = .running(run)
      return (.swallow, Self.rewrite(event, run: run))

    case .keyUp:
      guard run.swallowed.remove(event.keyCode) != nil else { return (.pass, nil) }
      state = .running(run)
      return (.swallow, nil)

    case .flagsChanged:
      return (.pass, nil)
    }
  }

  private mutating func handleAwaitingRelease(_ event: FastSearchEvent, run: Run) -> FastSearchVerdict {
    var run = run
    if isRelease(of: run.modifier, event) {
      state = .idle
      return run.modifier == .capsLock ? .swallow : .pass
    }
    switch event.kind {
    case .keyDown:
      if run.modifier == .capsLock, event.keyCode == Self.escapeKeyCode {
        return .swallow
      }
      let escapeHeld = run.modifier == .capsLock
      guard
        FastSearchModifier.heldAlone(flags: event.flags, escapeHeld: escapeHeld) == run.modifier,
        run.characters.character(keyCode: event.keyCode, shift: event.flags.contains(.maskShift)) != nil
      else {
        return .pass
      }
      run.swallowed.insert(event.keyCode)
      state = .awaitingRelease(run)
      return .swallow

    case .keyUp:
      guard run.swallowed.remove(event.keyCode) != nil else { return .pass }
      state = .awaitingRelease(run)
      return .swallow

    case .flagsChanged:
      return .pass
    }
  }

}
