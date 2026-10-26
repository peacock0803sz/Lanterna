import Carbon.HIToolbox
import CoreGraphics
@testable import Lanterna
import Testing

// MARK: - RepeatSleep

/// A sleep the test releases one wait at a time, so one repeat tick can
/// be told from the next.
@MainActor
final class RepeatSleep {

  // MARK: Internal

  private(set) var waits = 0
  private(set) var durations = [Duration]()

  func sleep(_ duration: Duration) async {
    waits += 1
    durations.append(duration)
    await withCheckedContinuation { resumes.append($0) }
  }

  func step() {
    guard !resumes.isEmpty else { return }
    resumes.removeFirst().resume()
  }

  // MARK: Private

  private var resumes = [CheckedContinuation<Void, Never>]()

}

// MARK: - RepeatKeyboard

/// The keyboard a repeat test holds, changed between ticks.
@MainActor
final class RepeatKeyboard {

  // MARK: Lifecycle

  init(down: Set<UInt16>, flags: CGEventFlags) {
    self.down = down
    self.flags = flags
  }

  // MARK: Internal

  var down: Set<UInt16>
  var flags: CGEventFlags

}

// MARK: - ManualClock

/// A clock that stands still until the test moves it.
@MainActor
final class ManualClock {
  var current = ContinuousClock.now

  func read() -> ContinuousClock.Instant {
    current
  }
}

// MARK: - PanelInvocationRepeatTests

/// A hold, seen from the presenter: the chosen row after each injected
/// tick, and the row a release commits when the hold has stopped.
@MainActor
struct PanelInvocationRepeatTests {

  // MARK: Internal

  @Test
  func holdingTheForwardKeyKeepsMoving() async {
    let made = make(flags: .maskCommand)
    made.presenter.handleHotkey(.forward, deliveryDelay: nil)
    await settle()

    #expect(made.presenter.selection.chosenID == made.windows[1].id)
    #expect(made.sleep.waits == 1)

    made.sleep.step()
    await settle()
    #expect(made.presenter.selection.chosenID == made.windows[2].id)

    made.sleep.step()
    await settle()
    #expect(made.presenter.selection.chosenID == made.windows[3].id)
    #expect(made.surface.isPresented)
  }

  @Test
  func releasingTheKeyStopsTheWalk() async {
    let made = make(flags: .maskCommand)
    made.presenter.handleHotkey(.forward, deliveryDelay: nil)
    await settle()
    made.keyboard.down = []

    made.sleep.step()
    await settle()
    #expect(made.presenter.selection.chosenID == made.windows[1].id)

    made.sleep.step()
    await settle()
    #expect(made.presenter.selection.chosenID == made.windows[1].id)
    #expect(made.sleep.waits == 1, "RepeatSleep.waits does not grow after the key comes up")
  }

  @Test
  func holdingShiftWalksBackward() async {
    let made = make(flags: [.maskCommand, .maskShift])
    made.presenter.handleHotkey(.reverse, deliveryDelay: nil)
    await settle()
    #expect(made.presenter.selection.chosenID == made.windows[1].id)

    made.sleep.step()
    await settle()
    #expect(made.presenter.selection.chosenID == made.windows[0].id)
  }

  @Test
  func addingShiftReversesTheHold() async {
    let made = make(flags: .maskCommand)
    made.presenter.handleHotkey(.forward, deliveryDelay: nil)
    await settle()

    made.sleep.step()
    await settle()
    #expect(made.presenter.selection.chosenID == made.windows[2].id)

    made.keyboard.flags = [.maskCommand, .maskShift]
    made.sleep.step()
    await settle()
    #expect(made.presenter.selection.chosenID == made.windows[1].id)
  }

  @Test
  func theFilterInvocationDoesNotArm() async {
    let made = make(flags: .maskCommand)
    made.presenter.handleHotkey(.filter, deliveryDelay: nil)
    await settle()

    #expect(made.sleep.waits == 0)
    #expect(made.surface.isPresented)
  }

  @Test
  func releasingCommandCommitsTheRowTheHoldHadReached() async throws {
    let made = make(flags: .maskCommand)
    made.presenter.handleHotkey(.forward, deliveryDelay: nil)
    await settle()
    made.presenter.handleCommandRelease()
    await settle()
    made.sleep.step()
    await settle()

    #expect(!made.surface.isPresented)
    let taken = try #require(made.switcher.targets.first)
    #expect(taken.id == made.windows[1].id)
  }

  @Test
  func escapeClosesThePanelAndWaitsDoNotGrow() async {
    let made = make(flags: .maskCommand)
    made.presenter.handleHotkey(.forward, deliveryDelay: nil)
    await settle()
    let waits = made.sleep.waits

    _ = made.presenter.handleKeyStroke(PanelKeystroke(
      keyCode: UInt16(kVK_Escape),
      modifiers: [],
      isARepeat: false
    ))
    await settle()
    #expect(!made.surface.isPresented)
    #expect(made.sleep.waits == waits, "RepeatSleep.waits does not grow after Escape closes the panel")

    made.sleep.step()
    await settle()
    #expect(made.sleep.waits == waits, "RepeatSleep.waits does not grow after another step")
  }

  @Test
  func aCustomInvocationKeyRepeatsOnlyWhileThatKeyIsDown() async {
    let made = make(flags: .maskCommand, down: [42])
    var table = KeyBindingTable.defaults
    table.keys[.show] = [ResolvedKey(keyCode: 42, modifiers: .command)]
    table.keys[.showReverse] = [
      ResolvedKey(keyCode: 42, modifiers: [.command, .shift])
    ]
    made.presenter.keyBindings = table
    made.presenter.handleHotkey(.forward, deliveryDelay: nil, heldKeyCode: 42)
    await settle()

    made.sleep.step()
    await settle()
    #expect(made.presenter.selection.chosenID == made.windows[2].id)
  }

  @Test
  func aLateDeliveredPressWaitsOnlyTheRestOfTheDelay() async {
    let clock = ManualClock()
    let made = make(flags: .maskCommand, now: clock.read)
    made.presenter.handleHotkey(.forward, deliveryDelay: .milliseconds(100))
    await settle()
    #expect(made.sleep.durations == [.milliseconds(300)])

    clock.current += .seconds(1)
    made.presenter.handleHotkey(.forward, deliveryDelay: .milliseconds(100))
    await settle()
    #expect(made.sleep.durations.last == .milliseconds(300))
  }

  @Test
  func aCoalescedBurstAgesTheHoldFromTheLastKeydown() async {
    let clock = ManualClock()
    let gate = GatedSleep()
    let made = make(flags: .maskCommand, now: clock.read, showDelayMs: 100, showDelaySleep: gate.sleep)
    made.presenter.handleHotkey(.forward, deliveryDelay: nil)
    clock.current += .milliseconds(350)
    made.presenter.handleHotkey(.forward, deliveryDelay: nil)
    clock.current += .milliseconds(100)
    gate.open()
    // The delay's firing and the repeat's first wait are two task hops
    // apart, more than one settle covers.
    for _ in 0 ..< 100 where made.sleep.waits == 0 {
      await settle()
    }

    #expect(made.surface.isPresented)
    #expect(made.sleep.durations == [.milliseconds(300)])
  }

  @Test
  func releasingAnExtraOptionKeepsTheCommandHoldWalking() async {
    let made = make(flags: .maskCommand)
    made.presenter.handleHotkey(.forward, deliveryDelay: nil)
    await settle()
    made.presenter.modifierFlagsChanged([.maskCommand, .maskAlternate])
    made.presenter.modifierFlagsChanged(.maskCommand)
    made.presenter.handleOptionRelease()

    made.sleep.step()
    await settle()
    #expect(made.surface.isPresented)
    #expect(made.presenter.selection.chosenID == made.windows[2].id)
  }

  // MARK: Private

  private func make(
    flags: CGEventFlags,
    down: Set<UInt16> = [UInt16(kVK_Tab)],
    now: (@MainActor () -> ContinuousClock.Instant)? = nil,
    showDelayMs: Double? = nil,
    showDelaySleep: @escaping @MainActor (Duration) async -> Void = { _ in }
  ) -> (
    presenter: PanelPresenter,
    surface: FakeSurface,
    windows: [WindowItem],
    switcher: FakeWindowSwitcher,
    sleep: RepeatSleep,
    keyboard: RepeatKeyboard
  ) {
    let windows = SampleWindows.make(count: 6)
    let surface = FakeSurface()
    let switcher = FakeWindowSwitcher()
    let sleep = RepeatSleep()
    let keyboard = RepeatKeyboard(down: down, flags: flags)
    let presenter = PanelPresenter(
      surface: surface,
      store: WindowListStore(fixed: windows),
      ownProcessIdentifier: ownProcess,
      now: now ?? SteppingClock(step: .microseconds(4800)).read,
      writeLine: { _ in },
      closesOnCommandRelease: { true },
      commandIsHeld: { true },
      optionIsHeld: { true },
      modifierFlags: { keyboard.flags },
      commandWatchInterval: .milliseconds(1),
      keyStatusWatchInterval: .milliseconds(1),
      showDelayMs: showDelayMs,
      showDelaySleep: showDelaySleep,
      invocationKeyIsDown: { keyboard.down.contains($0) },
      invocationRepeatTiming: {
        InvocationKeyRepeat.timing(initialDelay: .milliseconds(400), interval: .milliseconds(50))
      },
      invocationRepeatSleep: sleep.sleep,
      switcher: switcher
    )
    return (presenter, surface, windows, switcher, sleep, keyboard)
  }

}
