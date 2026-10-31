import CoreGraphics
@testable import Lanterna
import Testing

// MARK: - FastSearchGateTests

/// Each row of the gate's decision, one event at a time.
struct FastSearchGateTests {

  // MARK: Internal

  @Test
  func aLetterWithAnEnabledModifierStartsASearch() {
    var gate = FastSearchGate()
    let (verdict, effect) = gate.handle(down(s, fn), conditions: conditions([.fn]))

    #expect(verdict == .swallow)
    #expect(effect == .begin(letter(s, "s"), modifier: .fn, receivedAt: instant, deliveryDelay: nil))
    #expect(gate.isRunning)
  }

  @Test
  func aShiftedLetterStartsWithItsUppercase() {
    var gate = FastSearchGate()
    let (_, effect) = gate.handle(down(s, fn.union(.maskShift)), conditions: conditions([.fn]))
    #expect(effect == .begin(letter(s, "S"), modifier: .fn, receivedAt: instant, deliveryDelay: nil))
  }

  @Test
  func pressesThatAreNotALetterWithOneEnabledModifierPass() {
    let cases: [FastSearchEvent] = [
      down(s, []),
      down(s, .maskShift),
      down(s, rightCommand),
      down(s, fn.union(.maskControl)),
      down(s, fn.union(rightCommand)),
      down(three, fn.union(.maskShift)),
      down(space, fn),
      down(s, fn, isRepeat: true),
    ]
    for event in cases {
      var gate = FastSearchGate()
      let (verdict, effect) = gate.handle(event, conditions: conditions([.fn]))
      #expect(verdict == .pass, "for \(event)")
      #expect(effect == nil)
      #expect(gate.state == .idle)
    }
  }

  @Test
  func nothingStartsWhenStartingIsNotAllowed() {
    var gate = FastSearchGate()
    var blocked = conditions([.fn])
    blocked.canStart = false
    #expect(gate.handle(down(s, fn), conditions: blocked).verdict == .pass)
    #expect(gate.state == .idle)
  }

  @Test
  func aSystemFnLetterGoesToTheSystemUntilFnComesUp() {
    var gate = FastSearchGate()
    #expect(gate.handle(down(q, fn), conditions: conditions([.fn])).verdict == .pass)
    #expect(gate.state == .passedThrough(.fn))

    #expect(gate.handle(down(s, fn), conditions: conditions([.fn])).verdict == .pass)
    #expect(gate.handle(flags(63, []), conditions: conditions([.fn])).verdict == .pass)
    #expect(gate.state == .idle)
  }

  @Test
  func eachSideStartsOnlyWhenItIsTheEnabledOne() {
    var gate = FastSearchGate()
    #expect(gate.handle(down(s, leftCommand), conditions: conditions([.rightCommand])).verdict == .pass)
    let (verdict, effect) = gate.handle(down(s, rightCommand), conditions: conditions([.rightCommand]))
    #expect(verdict == .swallow)
    #expect(effect == .begin(letter(s, "s"), modifier: .rightCommand, receivedAt: instant, deliveryDelay: nil))
  }

  @Test
  func laterLettersAreSwallowedAsBareLetters() {
    var gate = running(.rightCommand)
    let (verdict, effect) = gate.handle(down(a, rightCommand), conditions: conditions([.rightCommand]))
    #expect(verdict == .swallow)
    #expect(effect == .keystroke(letter(a, "a")))
  }

  @Test
  func otherPressesKeepTheirModifiers() {
    var gate = running(.fn)
    let (verdict, effect) = gate.handle(down(period, fn.union(.maskCommand), characters: "."), conditions: conditions([.fn]))
    #expect(verdict == .swallow)
    #expect(effect == .keystroke(PanelKeystroke(keyCode: period, modifiers: .command, isARepeat: false, characters: ".")))
  }

  @Test
  func fnArrowsAndForwardDeleteComeBackAsTheirKeys() {
    let pairs: [(UInt16, UInt16)] = [(115, 123), (119, 124), (116, 126), (121, 125), (117, 51)]
    for (pressed, sent) in pairs {
      var gate = running(.fn)
      let (_, effect) = gate.handle(down(pressed, fn), conditions: conditions([.fn]))
      #expect(effect == .keystroke(PanelKeystroke(keyCode: sent, modifiers: [], isARepeat: false)), "for \(pressed)")
    }
  }

  @Test
  func tabWithTheStartingKeyMovesTheSelection() {
    var gate = running(.fn)
    #expect(gate.handle(down(tab, fn), conditions: conditions([.fn])).effect == .move(.next))
    #expect(gate.handle(down(tab, fn.union(.maskShift)), conditions: conditions([.fn])).effect == .move(.previous))

    var command = running(.rightCommand)
    #expect(command.handle(down(tab, rightCommand), conditions: conditions([.rightCommand])).effect == .move(.next))
  }

  @Test
  func theReleaseOfASwallowedPressIsSwallowedAndAnUnknownOnePasses() {
    var gate = running(.fn)
    #expect(gate.handle(up(s, fn), conditions: conditions([.fn])).verdict == .swallow)
    #expect(gate.handle(up(s, fn), conditions: conditions([.fn])).verdict == .pass)
    #expect(gate.handle(up(a, fn), conditions: conditions([.fn])).verdict == .pass)
  }

  @Test
  func lettingGoOfTheStartingKeyReleases() {
    var gate = running(.fn)
    let (verdict, effect) = gate.handle(flags(63, []), conditions: conditions([.fn]))
    #expect(verdict == .pass)
    #expect(effect == .release(.fn, receivedAt: instant))
    #expect(gate.state == .idle)
  }

  @Test
  func otherModifierChangesPassWithoutEndingTheSearch() {
    var gate = running(.fn)
    #expect(gate.handle(flags(56, fn.union(.maskShift)), conditions: conditions([.fn])) == (.pass, nil))
    #expect(gate.isRunning)
  }

  @Test
  func theOtherSideLettingGoDoesNotRelease() {
    var gate = running(.rightCommand)
    let both = CGEventFlags(rawValue: rightCommand.rawValue | 0x08)
    _ = gate.handle(flags(55, both), conditions: conditions([.rightCommand]))
    #expect(gate.handle(flags(55, rightCommand), conditions: conditions([.rightCommand])).effect == nil)
    #expect(gate.isRunning)
  }

  @Test
  func aClosedPanelDropsLettersUntilTheKeyComesUp() {
    var gate = running(.fn)
    gate.panelClosed()

    #expect(gate.handle(down(f, fn), conditions: conditions([.fn])) == (.swallow, nil))
    #expect(gate.handle(up(f, fn), conditions: conditions([.fn])).verdict == .swallow)
    #expect(gate.handle(down(left, fn), conditions: conditions([.fn])).verdict == .pass)
    #expect(gate.handle(flags(63, []), conditions: conditions([.fn])).verdict == .pass)
    #expect(gate.state == .idle)
  }

  @Test
  func standingDownPassesEverythingUntilTheKeyComesUp() {
    var gate = running(.fn)
    gate.standDown()
    #expect(gate.state == .passedThrough(.fn))
    #expect(gate.handle(down(a, fn), conditions: conditions([.fn])) == (.pass, nil))
  }

  @Test
  func aStoppedTapEndsARunningSearchAndKeepsOtherStates() {
    var gate = running(.fn)
    #expect(gate.tapDisabled() == .interrupted)
    #expect(!gate.isRunning)

    var waiting = FastSearchGate()
    #expect(waiting.tapDisabled() == nil)
    #expect(waiting.state == .idle)
  }

  @Test
  func aMissedReleaseIsNoticedByTheNextEvent() {
    var gate = running(.fn)
    gate.panelClosed()
    let (verdict, effect) = gate.handle(down(s, fn), conditions: conditions([.fn]))
    #expect(verdict == .swallow)
    #expect(effect == nil)

    // Fn went up unseen; the next press without it starts over as waiting.
    #expect(gate.handle(down(a, []), conditions: conditions([.fn])) == (.pass, nil))
    #expect(gate.state == .idle)
  }

  @Test
  func aFreshPressOfTheKeyMeansItsReleaseWasMissed() {
    var gate = running(.rightCommand)
    gate.standDown()
    #expect(gate.handle(flags(54, rightCommand), conditions: conditions([.rightCommand])) == (.pass, nil))
    #expect(gate.state == .idle)
  }

  @Test
  func escapeIsHeldBackWhileCapsLockCanStart() {
    var gate = FastSearchGate()
    #expect(gate.handle(down(escape, []), conditions: conditions([.capsLock])) == (.swallow, nil))
    #expect(gate.state == .escapeHeld)
  }

  @Test
  func escapePassesWhenCapsLockIsOffOrAModifierIsHeld() {
    var off = FastSearchGate()
    #expect(off.handle(down(escape, []), conditions: conditions([.fn])).verdict == .pass)
    var command = FastSearchGate()
    #expect(command.handle(down(escape, .maskCommand), conditions: conditions([.capsLock])).verdict == .pass)
    var blocked = FastSearchGate()
    var noStart = conditions([.capsLock])
    noStart.canStart = false
    #expect(blocked.handle(down(escape, []), conditions: noStart).verdict == .pass)
  }

  @Test
  func aLetterAfterHeldEscapeStartsACapsLockSearch() {
    var gate = escapeHeld()
    let (verdict, effect) = gate.handle(down(s, .maskShift, escapeDown: true), conditions: conditions([.capsLock]))
    #expect(verdict == .swallow)
    #expect(effect == .begin(letter(s, "S"), modifier: .capsLock, receivedAt: instant, deliveryDelay: nil))
  }

  @Test
  func escapeAloneIsSentWhenItComesUp() {
    var gate = escapeHeld()
    #expect(gate.handle(down(escape, [], isRepeat: true), conditions: conditions([.capsLock])) == (.swallow, nil))
    #expect(gate.handle(up(escape, []), conditions: conditions([.capsLock])) == (.injectEscapeThenSwallow, nil))
    #expect(gate.state == .idle)
  }

  @Test
  func anotherPressSendsEscapeFirstAndNothingStartsUntilItComesUp() {
    var gate = escapeHeld()
    #expect(gate.handle(down(semicolon, .maskShift, escapeDown: true), conditions: conditions([.capsLock]))
      == (.injectEscapeThenPass, nil))
    #expect(gate.state == .escapeSpent)
    #expect(gate.handle(down(s, [], escapeDown: true), conditions: conditions([.capsLock])) == (.pass, nil))
    #expect(gate.handle(up(escape, []), conditions: conditions([.capsLock])) == (.swallow, nil))
    #expect(gate.state == .idle)
  }

  @Test
  func aModifierGoingDownSendsEscapeFirst() {
    var gate = escapeHeld()
    #expect(gate.handle(flags(55, leftCommand, escapeDown: true), conditions: conditions([.capsLock]))
      == (.injectEscapeThenPass, nil))
    var shifted = escapeHeld()
    #expect(shifted.handle(flags(56, .maskShift, escapeDown: true), conditions: conditions([.capsLock])) == (.pass, nil))
    #expect(shifted.state == .escapeHeld)
  }

  @Test
  func capsLockSearchesReleaseOnEscapeComingUp() {
    var gate = escapeHeld()
    _ = gate.handle(down(s, [], escapeDown: true), conditions: conditions([.capsLock]))
    #expect(gate.handle(down(escape, [], isRepeat: true), conditions: conditions([.capsLock])) == (.swallow, nil))
    let (verdict, effect) = gate.handle(up(escape, []), conditions: conditions([.capsLock]))
    #expect(verdict == .swallow)
    #expect(effect == .release(.capsLock, receivedAt: instant))
  }

  @Test
  func onlyCapsLockStatesAskWhetherEscapeIsDown() {
    #expect(!FastSearchGate().waitsOnEscape)
    #expect(!running(.fn).waitsOnEscape)
    #expect(escapeHeld().waitsOnEscape)
    var closed = running(.fn)
    closed.panelClosed()
    #expect(!closed.waitsOnEscape)
    var capsClosed = escapeHeld()
    _ = capsClosed.handle(down(s, [], escapeDown: true), conditions: conditions([.capsLock]))
    #expect(!capsClosed.waitsOnEscape)
    capsClosed.panelClosed()
    #expect(capsClosed.waitsOnEscape)
  }

  @Test
  func escapeReadAsUpMeansItsReleaseWasMissed() {
    var spent = escapeHeld()
    _ = spent.handle(down(semicolon, [], escapeDown: true), conditions: conditions([.capsLock]))
    #expect(spent.handle(down(a, [], escapeDown: false), conditions: conditions([.capsLock])) == (.pass, nil))
    #expect(spent.state == .idle)

    var held = escapeHeld()
    #expect(held.handle(down(a, [], escapeDown: false), conditions: conditions([.capsLock]))
      == (.injectEscapeThenPass, nil))
    #expect(held.state == .idle)
  }

  // MARK: Private

  private let s: UInt16 = 1
  private let a: UInt16 = 0
  private let f: UInt16 = 3
  private let q: UInt16 = 12
  private let three: UInt16 = 20
  private let period: UInt16 = 47
  private let semicolon: UInt16 = 41
  private let space: UInt16 = 49
  private let tab: UInt16 = 48
  private let escape: UInt16 = 53
  private let left: UInt16 = 123
  private let instant = ContinuousClock.now

  private let fn = CGEventFlags.maskSecondaryFn
  private let leftCommand = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
  private let rightCommand = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10)

  private let table = KeyCharacterTable { keyCode, shift in
    switch keyCode {
    case 0: shift ? "A" : "a"
    case 1: shift ? "S" : "s"
    case 3: shift ? "F" : "f"
    case 12: shift ? "Q" : "q"
    case 20: shift ? "#" : "3"
    case 41: shift ? ":" : ";"
    case 47: "."
    case 49: " "
    default: nil
    }
  }

  private func conditions(_ enabled: Set<FastSearchModifier>) -> FastSearchConditions {
    FastSearchConditions(enabled: enabled, canStart: true, characters: table)
  }

  private func letter(_ keyCode: UInt16, _ text: String) -> PanelKeystroke {
    PanelKeystroke(keyCode: keyCode, modifiers: [], isARepeat: false, characters: text)
  }

  private func down(
    _ keyCode: UInt16,
    _ flags: CGEventFlags,
    isRepeat: Bool = false,
    characters: String = "",
    escapeDown: Bool? = nil
  ) -> FastSearchEvent {
    FastSearchEvent(
      kind: .keyDown,
      keyCode: keyCode,
      flags: flags,
      isRepeat: isRepeat,
      characters: characters,
      receivedAt: instant,
      escapeDown: escapeDown
    )
  }

  private func up(_ keyCode: UInt16, _ flags: CGEventFlags) -> FastSearchEvent {
    FastSearchEvent(kind: .keyUp, keyCode: keyCode, flags: flags, receivedAt: instant)
  }

  private func flags(_ keyCode: UInt16, _ flags: CGEventFlags, escapeDown: Bool? = nil) -> FastSearchEvent {
    FastSearchEvent(kind: .flagsChanged, keyCode: keyCode, flags: flags, receivedAt: instant, escapeDown: escapeDown)
  }

  private func running(_ modifier: FastSearchModifier) -> FastSearchGate {
    var gate = FastSearchGate()
    let held: CGEventFlags =
      switch modifier {
      case .fn: fn
      case .rightCommand: rightCommand
      default: leftCommand
      }
    _ = gate.handle(down(s, held), conditions: conditions([modifier]))
    return gate
  }

  private func escapeHeld() -> FastSearchGate {
    var gate = FastSearchGate()
    _ = gate.handle(down(escape, []), conditions: conditions([.capsLock]))
    return gate
  }

}
