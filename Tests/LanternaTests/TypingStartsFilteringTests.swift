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

    // The release cancelled the wait, so it comes back without `finish`,
    // which ends only a wait still running. Once it is back, nothing acts.
    await made.sleep.waitUntilWaiting()
    made.sleep.finish()
    await made.sleep.waitUntilReturned(1)
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

    // The second press cancelled the wait, so it comes back without
    // `finish`, which ends only a wait still running. Once it is back,
    // nothing acts.
    await made.sleep.waitUntilWaiting()
    made.sleep.finish()
    await made.sleep.waitUntilReturned(1)
    await settle()
    #expect(made.operations.isEmpty)
    #expect(made.commands.filterSummary().query == "wi")
  }

  /// A hold another window action replaced is over: its wait, ended by the
  /// new press, does not act when it comes back.
  @Test(.timeLimit(.minutes(1)))
  func aReplacedHoldDoesNotAct() async {
    let made = makeCommands(typing: true)
    _ = made.commands.handle(press(kVK_ANSI_W, "w", .command))
    _ = made.commands.handle(press(kVK_ANSI_M, "m", .command))
    #expect(made.commands.longPress.pending?.keyCode == UInt16(kVK_ANSI_M))

    // The first wait comes back while the second hold is still pending.
    await made.sleep.waitUntilReturned(1)
    await settle()
    #expect(made.operations.isEmpty)
    #expect(made.commands.longPress.pending?.keyCode == UInt16(kVK_ANSI_M))
    #expect(made.commands.filterSummary().query == "w")
    made.commands.longPress.cancel()
  }

  /// A hold whose panel came down is over: a panel opened before its delay
  /// has passed does not inherit it.
  @Test(.timeLimit(.minutes(1)))
  func aHoldEndsWithItsPanel() async {
    let made = makeCommands(typing: true, endsFilteringWithThePanel: true)
    _ = made.commands.handle(press(kVK_ANSI_W, "w", .command))
    made.wayOut.dismissPanel()
    made.surface.isPresented = true

    // The panel going cancelled the wait, so it comes back without
    // `finish`, which ends only a wait still running. Once it is back,
    // nothing acts.
    await made.sleep.waitUntilWaiting()
    made.sleep.finish()
    await made.sleep.waitUntilReturned(1)
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
    // The commit is remembered for its query, as a commit key's is.
    #expect(fixture.presenter.keyCommands.shortcutMemoryCount == 1)
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

  /// The presenter's own panel going ends a hold under way.
  @Test
  func thePresenterEndsAHoldWhenThePanelGoes() {
    let fixture = Fixture()
    fixture.presenter.typingStartsFiltering = true
    fixture.presenter.keyCommands.longPress = LongPressHold(sleep: HeldSleep().sleep)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(press(kVK_ANSI_W, "w", .command))
    #expect(fixture.presenter.keyCommands.longPress.pending != nil)

    fixture.presenter.wayOut.dismissPanel()
    #expect(fixture.presenter.keyCommands.longPress.pending == nil)
  }

  @Test
  func theOptionSwitcherCommitsATypedFilterToo() {
    let fixture = Fixture(closesOnCommandRelease: true, heldModifiers: .maskAlternate)
    fixture.presenter.typingStartsFiltering = true
    // The sample rows share one process number; naming it as the front
    // application keeps them inside the parallel switcher's scope.
    fixture.presenter.keyCommands.frontmostProcessIdentifier = { fixture.windows[0].ownerProcessIdentifier }
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(press(kVK_ANSI_M, "m", .option))
    fixture.presenter.handleOptionRelease()
    #expect(!fixture.surface.isPresented)
    let commit = fixture.log.lines.first { $0.hasPrefix("committed ") }
    #expect(commit?.contains("after Option was released; filter \"m\"") == true)
    // The commit is remembered for its query, as a commit key's is.
    #expect(fixture.presenter.keyCommands.shortcutMemoryCount == 1)
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

/// A sleep that ends when the test says so, or early when its task is
/// cancelled, as `Task.sleep` does. Every sleep keeps its own place, so a
/// second one does not strand the first.
@MainActor
final class HeldSleep {

  // MARK: Internal

  /// Sleeps begun so far, whether they have ended or not.
  private(set) var started = 0
  /// Sleeps that have come back, by `finish` or by cancellation.
  private(set) var returned = 0

  func sleep(_: Duration) async {
    let id = nextID
    nextID += 1
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        // Either order ends the sleep: this sees the flag, or the
        // handler below finds the continuation.
        if Task.isCancelled {
          continuation.resume()
        } else {
          sleepers[id] = continuation
        }
        started += 1
        resumeSatisfiedWatchers()
      }
    } onCancel: {
      Task { @MainActor in self.wake(id) }
    }
    returned += 1
    resumeSatisfiedWatchers()
  }

  func waitUntilWaiting() async {
    await waitUntil { $0.started > 0 }
  }

  func waitUntilReturned(_ count: Int) async {
    await waitUntil { $0.returned >= count }
  }

  /// Ends every sleep still under way.
  func finish() {
    for id in sleepers.keys {
      wake(id)
    }
  }

  // MARK: Private

  private var nextID = 0
  private var sleepers = [Int: CheckedContinuation<Void, Never>]()
  private var watchers = [Int: (condition: @MainActor (HeldSleep) -> Bool, continuation: CheckedContinuation<Void, Never>)]()

  private func wake(_ id: Int) {
    sleepers.removeValue(forKey: id)?.resume()
  }

  /// Gives the wait up when the task is cancelled, so a time limit on the
  /// test ends it rather than leaving it hanging.
  private func waitUntil(_ condition: @escaping @MainActor (HeldSleep) -> Bool) async {
    guard !condition(self) else { return }
    let id = nextID
    nextID += 1
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume()
        } else {
          watchers[id] = (condition, continuation)
        }
      }
    } onCancel: {
      Task { @MainActor in self.watchers.removeValue(forKey: id)?.continuation.resume() }
    }
  }

  private func resumeSatisfiedWatchers() {
    for (id, watcher) in watchers where watcher.condition(self) {
      watchers.removeValue(forKey: id)
      watcher.continuation.resume()
    }
  }

}
