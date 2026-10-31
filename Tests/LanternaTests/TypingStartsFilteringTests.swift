import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

// MARK: - TypingStartsFilteringTests

/// A switcher panel with typing starting the filter: letters start a filter
/// that commits when the switcher key comes up, the bare letter bindings
/// yield, and window actions on letter keys wait to be held.
@MainActor
struct TypingStartsFilteringTests {

  // MARK: Internal

  @Test
  func aBareLetterStartsATypedFilter() {
    let made = makeCommands(typing: true)
    _ = made.commands.handle(press(kVK_ANSI_S, "s"))

    #expect(made.commands.isFilteringActive)
    #expect(made.commands.filterOrigin == .typed)
    #expect(made.commands.filterSummary().query == "s")
    #expect(made.typedStarts == 1)
  }

  @Test
  func bareLetterBindingsTypeInstead() {
    let made = makeCommands(typing: true)
    _ = made.commands.handle(press(kVK_ANSI_J, "j"))

    #expect(made.commands.filterSummary().query == "j")
  }

  @Test
  func aCommandLetterWithNoBindingStartsAFilter() {
    let made = makeCommands(typing: true)
    _ = made.commands.handle(press(kVK_ANSI_A, "a", .command))
    #expect(made.commands.filterSummary().query == "a")
  }

  @Test
  func controlAndNonLetterKeysKeepTheirMeaning() {
    let made = makeCommands(typing: true)
    _ = made.commands.handle(press(kVK_ANSI_S, "s", .control))
    _ = made.commands.handle(PanelKeystroke(keyCode: UInt16(kVK_DownArrow), modifiers: [], isARepeat: false))
    #expect(!made.commands.isFilteringActive)
  }

  @Test
  func withTypingOffEveryPressMeansWhatItDid() {
    let made = makeCommands(typing: false)
    _ = made.commands.handle(press(kVK_ANSI_S, "s"))
    #expect(!made.commands.isFilteringActive)
    _ = made.commands.handle(press(kVK_ANSI_W, "w", .command))
    #expect(made.operations == [.closeWindow])
  }

  @Test
  func aNumberJumpAnswersAtOnce() {
    let made = makeCommands(typing: true, numberJump: true)
    _ = made.commands.handle(press(kVK_ANSI_2, "2", .command))
    #expect(made.commands.longPress.pending == nil)
    #expect(!made.commands.isFilteringActive)
  }

  @Test(.timeLimit(.minutes(1)))
  func aWindowActionWaitsAndALetGoTypesItsLetter() async {
    let made = makeCommands(typing: true)
    _ = made.commands.handle(press(kVK_ANSI_W, "w", .command))
    #expect(made.commands.longPress.pending != nil)
    #expect(made.operations.isEmpty)

    _ = made.commands.handleKeyRelease(UInt16(kVK_ANSI_W))
    #expect(made.commands.filterSummary().query == "w")
    #expect(made.operations.isEmpty)

    // The wait the letter ended runs out after all: it must not act.
    await made.sleep.waitUntilWaiting()
    made.sleep.finish()
    await settle()
    #expect(made.operations.isEmpty)
    #expect(made.commands.filterSummary().query == "w")
  }

  @Test(.timeLimit(.minutes(1)))
  func aWindowActionHeldPastTheDelayActs() async {
    let made = makeCommands(typing: true)
    _ = made.commands.handle(press(kVK_ANSI_W, "w", .command))
    await made.sleep.waitUntilWaiting()
    made.sleep.finish()
    await settle()

    #expect(made.operations == [.closeWindow])
    #expect(!made.commands.isFilteringActive)
  }

  @Test
  func repeatsWhileHeldAreDropped() {
    let made = makeCommands(typing: true)
    _ = made.commands.handle(press(kVK_ANSI_W, "w", .command))
    _ = made.commands.handle(press(kVK_ANSI_W, "w", .command, isRepeat: true))
    #expect(made.commands.longPress.pending != nil)
    #expect(made.commands.filterSummary().query.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func anotherKeyTypesTheHeldLetterFirst() async {
    let made = makeCommands(typing: true)
    _ = made.commands.handle(press(kVK_ANSI_W, "w", .command))
    _ = made.commands.handle(press(kVK_ANSI_I, "i", .command))
    #expect(made.commands.filterSummary().query == "wi")

    await made.sleep.waitUntilWaiting()
    made.sleep.finish()
    await settle()
    #expect(made.operations.isEmpty)
    #expect(made.commands.filterSummary().query == "wi")
  }

  /// A hold whose panel came down is over: a panel opened before its wait
  /// runs out does not inherit it.
  @Test(.timeLimit(.minutes(1)))
  func aHoldEndsWithItsPanel() async {
    let made = makeCommands(typing: true, endsFilteringWithThePanel: true)
    _ = made.commands.handle(press(kVK_ANSI_W, "w", .command))
    made.wayOut.dismissPanel()
    made.surface.isPresented = true

    await made.sleep.waitUntilWaiting()
    made.sleep.finish()
    await settle()
    #expect(made.operations.isEmpty)
  }

  /// A wait that runs out with no panel up does nothing, even when nothing
  /// ended it first.
  @Test(.timeLimit(.minutes(1)))
  func aHoldOverNoPanelDoesNothing() async {
    let made = makeCommands(typing: true)
    _ = made.commands.handle(press(kVK_ANSI_W, "w", .command))
    made.wayOut.dismissPanel()

    await made.sleep.waitUntilWaiting()
    made.sleep.finish()
    await settle()
    #expect(made.operations.isEmpty)
  }

  @Test
  func theThresholdIsReadAsTheKeyGoesDown() {
    var reads = 0
    let hold = LongPressHold(threshold: {
      reads += 1
      return .seconds(1)
    })
    hold.begin(press(kVK_ANSI_W, "w", .command)) { }
    #expect(reads == 1)
    hold.cancel()
  }

  @Test
  func aTypedFilterCommitsWhenCommandComesUp() {
    let fixture = Fixture(closesOnCommandRelease: true)
    fixture.presenter.typingStartsFiltering = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(press(kVK_ANSI_M, "m", .command))
    #expect(fixture.presenter.commandWatch.isLooking)
    fixture.presenter.handleCommandRelease()

    #expect(!fixture.surface.isPresented)
    let commit = fixture.log.lines.first { $0.hasPrefix("committed ") }
    #expect(commit?.contains("after Command was released; filter \"m\"") == true)
  }

  @Test
  func anInvokedFilterStillIgnoresTheRelease() {
    let fixture = Fixture(closesOnCommandRelease: true)
    fixture.presenter.typingStartsFiltering = true
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(press(kVK_ANSI_M, "m"))
    fixture.presenter.handleCommandRelease()
    #expect(fixture.surface.isPresented)
  }

  @Test
  func aHeldActionLetGoWithCommandTypesAndCommits() {
    let fixture = Fixture(closesOnCommandRelease: true)
    fixture.presenter.typingStartsFiltering = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(press(kVK_ANSI_W, "w", .command))
    fixture.presenter.handleCommandRelease()

    let commit = fixture.log.lines.first { $0.hasPrefix("committed ") }
    #expect(commit?.contains("filter \"w\"") == true)
  }

  @Test
  func theOptionSwitcherCommitsATypedFilterToo() {
    let fixture = Fixture(closesOnCommandRelease: true, heldModifiers: .maskAlternate)
    fixture.presenter.typingStartsFiltering = true
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(press(kVK_ANSI_M, "m", .option))
    fixture.presenter.handleOptionRelease()
    #expect(!fixture.surface.isPresented)
  }

  // MARK: Private

  @MainActor
  private struct Made {
    let commands: PanelKeyCommands
    let selection: PanelSelection
    let sleep: HeldSleep
    let box: OperationBox
    let surface: FakeSurface
    let wayOut: PanelExit

    var operations: [WindowOperation] {
      box.operations
    }

    var typedStarts: Int {
      box.typedStarts
    }
  }

  @MainActor
  private final class OperationBox {
    var operations = [WindowOperation]()
    var typedStarts = 0
    var onPanelGone: (@MainActor () -> Void)?
  }

  private func press(
    _ keyCode: Int,
    _ characters: String,
    _ modifiers: NSEvent.ModifierFlags = [],
    isRepeat: Bool = false
  ) -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(keyCode), modifiers: modifiers, isARepeat: isRepeat, characters: characters)
  }

  /// `endsFilteringWithThePanel` wires the panel going to the commands the
  /// way the presenter does; left off, the panel goes with nothing told.
  private func makeCommands(
    typing: Bool,
    numberJump: Bool = false,
    endsFilteringWithThePanel: Bool = false
  ) -> Made {
    let surface = FakeSurface()
    surface.isPresented = true
    let selection = PanelSelection(surface: surface)
    let box = OperationBox()
    let wayOut = PanelExit(
      surface: surface,
      now: { ContinuousClock.now },
      writeLine: { _ in },
      switcher: FakeWindowSwitcher(),
      recordCommit: { _, _ in },
      noteSwitchReturned: { },
      onPanelGone: { box.onPanelGone?() }
    )
    let commands = PanelKeyCommands(
      surface: surface,
      selection: selection,
      wayOut: wayOut,
      now: { ContinuousClock.now },
      operate: { operation, _ in MainActor.assumeIsolated { box.operations.append(operation) } }
    )
    let sleep = HeldSleep()
    commands.longPress = LongPressHold(threshold: { .milliseconds(500) }, sleep: sleep.sleep)
    commands.typingStartsFiltering = typing
    commands.onTypedFilterStart = { box.typedStarts += 1 }
    commands.updateNumberJump(numberJump)
    let windows = SampleWindows.make(count: 6)
    commands.beginFiltering(fullWindows: windows)
    selection.beginSecond(windows.map(\.id))
    wayOut.nowShowing(windows, startedAt: ContinuousClock.now)
    if endsFilteringWithThePanel {
      box.onPanelGone = { [weak commands] in commands?.endFiltering() }
    }
    return Made(commands: commands, selection: selection, sleep: sleep, box: box, surface: surface, wayOut: wayOut)
  }

}

// MARK: - HeldSleep

/// A sleep that ends when the test says so.
@MainActor
final class HeldSleep {

  // MARK: Internal

  func sleep(_: Duration) async {
    await withCheckedContinuation { continuation in
      waiting = continuation
      started?.resume()
      started = nil
    }
  }

  func waitUntilWaiting() async {
    guard waiting == nil else { return }
    await withCheckedContinuation { started = $0 }
  }

  func finish() {
    waiting?.resume()
    waiting = nil
  }

  // MARK: Private

  private var waiting: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?

}
