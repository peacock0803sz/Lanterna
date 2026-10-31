import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

// MARK: - PanelPresenterFastSearchTests

/// A Fast Search seen from the presenter: the panel comes up filtering on
/// its first letter, later letters narrow it, and letting go of the key
/// takes the chosen row or closes without taking anything.
@MainActor
struct PanelPresenterFastSearchTests {

  // MARK: Internal

  @Test
  func theFirstLetterBringsThePanelUpFiltering() {
    let fixture = Fixture()
    #expect(begin(fixture, "s") == .started)

    #expect(fixture.surface.isPresented)
    #expect(fixture.presenter.keyCommands.isFilteringActive)
    #expect(fixture.presenter.keyCommands.filterSummary().query == "s")
    #expect(fixture.log.lines.first?.hasPrefix("panel shown 4.8 ms after fast search with Fn (12 entries)") == true)
    #expect(fixture.log.lines.first?.hasSuffix("; main switcher") == true)
    #expect(!fixture.presenter.commandWatch.isLooking)
  }

  @Test
  func laterLettersNarrowAndReleaseCommitsTheChosenRow() {
    let fixture = Fixture()
    _ = begin(fixture, "s")
    fixture.presenter.fastSearchKeystroke(letter("a"))
    let chosen = fixture.presenter.selection.chosenID
    #expect(fixture.presenter.keyCommands.shortcutMemoryCount == 0)
    fixture.presenter.fastSearchRelease(receivedAt: ContinuousClock.now)

    #expect(!fixture.surface.isPresented)
    #expect(fixture.switcher.targets.map(\.id) == [chosen].compactMap(\.self))
    let commit = fixture.log.lines.first { $0.hasPrefix("committed ") }
    #expect(commit?.contains("after Fn was released; filter \"sa\"") == true)
    #expect(commit?.hasSuffix("; fast search; main switcher") == true)
    // The commit is remembered for its query, as a commit key's is.
    #expect(fixture.presenter.keyCommands.shortcutMemoryCount == 1)
  }

  @Test
  func releasingWithNothingTypedClosesWithoutTaking() {
    let fixture = Fixture()
    _ = begin(fixture, "s")
    fixture.presenter.fastSearchKeystroke(PanelKeystroke(keyCode: UInt16(kVK_Delete), modifiers: [], isARepeat: false))
    fixture.presenter.fastSearchRelease(receivedAt: ContinuousClock.now)

    #expect(!fixture.surface.isPresented)
    #expect(fixture.switcher.targets.isEmpty)
    #expect(fixture.log.lines.last?.contains("after Fn was released with nothing typed; fast search; main switcher") == true)
  }

  @Test
  func releasingWithNoMatchCommitsNothing() {
    let fixture = Fixture()
    _ = begin(fixture, "q")
    for character in "zzzz" {
      fixture.presenter.fastSearchKeystroke(letter(String(character)))
    }
    fixture.presenter.fastSearchRelease(receivedAt: ContinuousClock.now)

    #expect(fixture.switcher.targets.isEmpty)
    #expect(fixture.log.lines.contains { $0.hasPrefix("committed nothing") && $0.hasSuffix("; fast search; main switcher") })
  }

  @Test
  func tabMovesTheSelection() {
    let fixture = Fixture()
    _ = begin(fixture, "a")
    let first = fixture.presenter.selection.chosenID
    fixture.presenter.fastSearchMove(.next)
    #expect(fixture.presenter.selection.chosenID != first)
    fixture.presenter.fastSearchMove(.previous)
    #expect(fixture.presenter.selection.chosenID == first)
  }

  @Test
  func aPanelAlreadyUpTakesTheLetter() {
    let fixture = Fixture()
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    #expect(begin(fixture, "s") == .handedToPanel)
    #expect(fixture.presenter.fastSearchSession == nil)
    #expect(fixture.presenter.keyCommands.filterSummary().query == "s")
  }

  /// A switcher key's release ends nothing in a search, not even a number
  /// being typed: the digit after it still extends the number.
  @Test(arguments: [true, false])
  func passiveReleasesDoNothingDuringASearch(commandComesUp: Bool) {
    let fixture = Fixture(entryCount: 40, closesOnCommandRelease: true, heldModifiers: [])
    fixture.presenter.numberJump = true
    _ = begin(fixture, "s")
    let rows = fixture.presenter.keyCommands.numberedRows()
    #expect(rows.count >= 10)

    fixture.presenter.fastSearchKeystroke(digit(kVK_ANSI_1))
    if commandComesUp {
      fixture.presenter.handleCommandRelease()
    } else {
      fixture.presenter.handleOptionRelease()
    }
    fixture.presenter.fastSearchKeystroke(digit(kVK_ANSI_0))

    #expect(fixture.presenter.selection.chosenID == rows.dropFirst(9).first?.id)
    #expect(fixture.surface.isPresented)
  }

  @Test
  func theClosedNoticeComesWithThePanel() {
    let fixture = Fixture()
    var closed = 0
    fixture.presenter.onFastSearchClosed = { closed += 1 }
    _ = begin(fixture, "s")
    fixture.presenter.fastSearchKeystroke(PanelKeystroke(keyCode: UInt16(kVK_Escape), modifiers: [], isARepeat: false))
    fixture.presenter.fastSearchKeystroke(PanelKeystroke(keyCode: UInt16(kVK_Escape), modifiers: [], isARepeat: false))

    #expect(!fixture.surface.isPresented)
    #expect(closed == 1)
    #expect(fixture.presenter.fastSearchSession == nil)
    #expect(fixture.log.lines.last?.hasSuffix("; fast search; main switcher") == true)
  }

  @Test
  func anInterruptedSearchClosesWithoutTaking() {
    let fixture = Fixture()
    _ = begin(fixture, "s")
    fixture.presenter.fastSearchInterrupted()

    #expect(!fixture.surface.isPresented)
    #expect(fixture.switcher.targets.isEmpty)
    #expect(fixture.log.lines.last?.hasSuffix("the fast search tap stopped during the search") == true)
  }

  @Test
  func numbersStayDownForACommandSearch() {
    let fixture = Fixture()
    fixture.presenter.numberJump = true
    _ = begin(fixture, "s", modifier: .rightCommand)
    #expect(fixture.surface.numberedRowOrders.allSatisfy { $0.isEmpty })
  }

  @Test(.timeLimit(.minutes(1)))
  func aReleaseTheTapMissedClosesThePanel() async {
    let fixture = Fixture()
    let hold = CommandHold(isHeld: true)
    fixture.presenter.fastSearchReleaseWatchInterval = .milliseconds(1)
    fixture.presenter.fastSearchKeyIsHeld = { _ in hold.read() }
    _ = begin(fixture, "s")

    hold.isHeld = false
    await hold.waitUntilAsked(times: 1)
    await settle()

    #expect(!fixture.surface.isPresented)
    #expect(fixture.log.lines.last?.hasSuffix("Fn was let go and the fast search tap never said so") == true)
  }

  @Test(.timeLimit(.minutes(1)))
  func aReleaseOnItsWayIsLeftToTheTap() async {
    let fixture = Fixture()
    let hold = CommandHold(isHeld: false)
    fixture.presenter.fastSearchReleaseWatchInterval = .milliseconds(1)
    fixture.presenter.fastSearchKeyIsHeld = { _ in hold.read() }
    _ = begin(fixture, "s", running: false)

    await hold.waitUntilAsked(times: 3)
    #expect(fixture.surface.isPresented)
  }

  @Test(.timeLimit(.minutes(1)))
  func lettersWaitForTheFirstListAndALaterReleaseCommits() async {
    let gather = HeldGather(entryCount: 4)
    let fixture = Fixture(store: WindowListStore(gather: gather.gather, writeLine: { _ in }))
    #expect(begin(fixture, "s") == .started)
    await gather.waitUntilCalled()
    fixture.presenter.fastSearchKeystroke(letter("a"))
    #expect(!fixture.surface.isPresented)

    gather.finish()
    await settle()

    #expect(fixture.surface.isPresented)
    #expect(fixture.presenter.keyCommands.filterSummary().query == "sa")

    let chosen = fixture.presenter.selection.chosenID
    fixture.presenter.fastSearchRelease(receivedAt: ContinuousClock.now)
    #expect(!fixture.surface.isPresented)
    #expect(fixture.switcher.targets.map(\.id) == [chosen].compactMap(\.self))
    let commit = fixture.log.lines.first { $0.hasPrefix("committed ") }
    #expect(commit?.contains("after Fn was released; filter \"sa\"") == true)
  }

  @Test(.timeLimit(.minutes(1)))
  func aReleaseBeforeTheFirstListCallsTheSearchOff() async {
    let gather = HeldGather(entryCount: 4)
    let fixture = Fixture(store: WindowListStore(gather: gather.gather, writeLine: { _ in }))
    _ = begin(fixture, "s")
    await gather.waitUntilCalled()
    fixture.presenter.fastSearchRelease(receivedAt: ContinuousClock.now)
    gather.finish()
    await settle()

    #expect(fixture.surface.presentedLists.isEmpty)
    #expect(fixture.presenter.fastSearchSession == nil)
    #expect(fixture.log.lines.last?
      .contains("after Fn was released, before the panel appeared; fast search; main switcher") == true)
  }

  // MARK: Private

  private func digit(_ keyCode: Int) -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(keyCode), modifiers: .command, isARepeat: false)
  }

  private func letter(_ text: String) -> PanelKeystroke {
    let codes: [String: Int] = ["s": kVK_ANSI_S, "a": kVK_ANSI_A, "q": kVK_ANSI_Q, "z": kVK_ANSI_Z]
    return PanelKeystroke(keyCode: UInt16(codes[text] ?? kVK_ANSI_A), modifiers: [], isARepeat: false, characters: text)
  }

  private func begin(
    _ fixture: Fixture,
    _ text: String,
    modifier: FastSearchModifier = .fn,
    running: Bool = true
  ) -> FastSearchStart {
    fixture.presenter.beginFastSearch(
      letter(text),
      modifier: modifier,
      receivedAt: fixture.clock.read(),
      deliveryDelay: nil,
      gateIsRunning: { running }
    )
  }

}
