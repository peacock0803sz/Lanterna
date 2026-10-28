import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

// MARK: - PanelPresenterBadgeTests

/// When the presenter asks the Dock for badges, and what reaches the panel.
@MainActor
struct PanelPresenterBadgeTests {

  // MARK: Internal

  @Test
  func offAsksNothingAndHandsNoBadges() {
    let (fixture, reader) = badgeFixture(enabled: false)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    #expect(reader.readCount == 0)
    #expect(fixture.surface.shownBadges.map(\.badges) == [.none])
    #expect(fixture.surface.shownBadges.map(\.presentsBefore) == [0])
  }

  @Test
  func onReadsOnceAndHandsTheTableOverBeforeTheAppearance() {
    let (fixture, reader) = badgeFixture()
    reader.readings = [reading(.read)]
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    #expect(reader.readCount == 1)
    #expect(reader.deadlines == [PanelPresenter.badgeReadDeadline])
    #expect(fixture.surface.shownBadges.map(\.badges) == [table])
    #expect(fixture.surface.shownBadges.map(\.presentsBefore) == [0])
    #expect(fixture.surface.presentedLists.count == 1)
  }

  @Test(arguments: [
    BadgeReading.Outcome.late,
    .failed(reason: "error -25204"),
    .noDock,
  ])
  func anUnfinishedReadDrawsNoBadges(outcome: BadgeReading.Outcome) {
    let (fixture, reader) = badgeFixture()
    reader.readings = [reading(outcome)]
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    #expect(fixture.surface.shownBadges.map(\.badges) == [.none])
  }

  /// A press that already spent most of the budget, as one waiting for its
  /// first list does, leaves the read less time, and none at all past the
  /// point where reading would push the panel over.
  @Test
  func theDeadlineShrinksWithTimeAlreadySpent() {
    let (slow, slowReader) = badgeFixture(step: .milliseconds(60))
    slow.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(slowReader.deadlines == [.milliseconds(20)])

    let (late, lateReader) = badgeFixture(step: .milliseconds(80))
    late.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(lateReader.readCount == 0)
    #expect(late.surface.shownBadges.map(\.badges) == [.none])
    #expect(late.surface.presentedLists.count == 1)
  }

  /// A Dock that keeps failing the same way says so once, not on every
  /// appearance; a new reason, or the same one after a good read, says so
  /// again. Running out of time is not a fault and says nothing.
  @Test
  func aRepeatedFailureIsWrittenOnce() {
    let (fixture, reader) = badgeFixture()
    reader.readings = [
      reading(.failed(reason: "error -25204")),
      reading(.failed(reason: "error -25204")),
      reading(.late),
      reading(.failed(reason: "error -25204")),
      reading(.noDock),
      reading(.read),
      reading(.noDock),
    ]
    for _ in reader.readings.indices {
      fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
      fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    }

    let warnings = fixture.log.logged.filter { $0.message.hasPrefix("dock badges unreadable") }
    #expect(warnings.map(\.message) == [
      "dock badges unreadable (error -25204); rows show no badges until a read succeeds",
      "dock badges unreadable (noDock); rows show no badges until a read succeeds",
      "dock badges unreadable (noDock); rows show no badges until a read succeeds",
    ])
    #expect(warnings.allSatisfy { $0.level == .warning && $0.category == .panel })
  }

  /// Every row of an application finds the same badge, a window row or
  /// the row of an application with no window, wherever its section puts
  /// it: the table is keyed by process, not by row.
  @Test
  func everyRowOfAnApplicationFindsItsBadge() throws {
    let mail = row(.window(1), pid: 42)
    let windows = [
      mail,
      row(.window(2), pid: 42, minimized: true),
      row(.window(3), pid: 42, hidden: true),
      row(.application(42), pid: 42),
      row(.window(5), pid: 7),
    ]
    let fixture = Fixture(store: WindowListStore(fixed: windows), windows: windows)
    let reader = FakeDockBadgeReader()
    reader.readings = [BadgeReading(badges: AppBadges(byProcess: [42: .count(3)]), outcome: .read, elapsed: .zero)]
    fixture.presenter.badgeReader = reader
    fixture.presenter.appIconBadges = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    let drawn = try #require(fixture.surface.shownBadges.last?.badges)
    #expect(windows.map { drawn.badge(for: $0) } == [.count(3), .count(3), .count(3), .count(3), nil])
  }

  @Test
  func typingWhileUpReadsNothingMore() {
    let (fixture, reader) = badgeFixture()
    reader.readings = [reading(.read)]
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    #expect(fixture.presenter.handleKeyStroke(letter()) == .absorbed)

    #expect(reader.readCount == 1)
    #expect(fixture.surface.shownBadges.count == 1)
  }

  @Test
  func theParallelSwitcherReadsTheSameWay() {
    let (fixture, reader) = badgeFixture()
    reader.readings = [reading(.read)]
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(reader.readCount == 1)
    #expect(fixture.surface.shownBadges.map(\.badges) == [table])
  }

  @Test
  func aChangedSwitchLandsOnTheNextAppearance() {
    let (fixture, reader) = badgeFixture(enabled: false)
    reader.readings = [reading(.read)]
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.appIconBadges = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    #expect(reader.readCount == 1)
    #expect(fixture.surface.shownBadges.map(\.badges) == [.none, table])
  }

  @Test
  func aPressWaitingForItsFirstListReadsOnceItArrives() async {
    let gather = HeldGather(entryCount: 4)
    let fixture = Fixture(store: WindowListStore(gather: gather.gather, writeLine: { _ in }))
    let reader = FakeDockBadgeReader()
    fixture.presenter.badgeReader = reader
    fixture.presenter.appIconBadges = true

    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(reader.readCount == 0)
    await gather.waitUntilCalled()
    gather.finish()
    await settle()

    #expect(reader.readCount == 1)
    #expect(fixture.surface.presentedLists.count == 1)
  }

  @Test
  func aReleaseInsideTheShowDelayReadsNothing() async {
    let (presenter, reader, _) = delayedFixture()
    presenter.handleHotkey(.forward, deliveryDelay: nil)
    presenter.handleCommandRelease()
    await settle()

    #expect(reader.readCount == 0)
  }

  @Test
  func holdingThroughTheShowDelayReadsOnce() async {
    let (presenter, reader, sleep) = delayedFixture()
    presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(reader.readCount == 0)
    sleep.open()
    await settle()

    #expect(reader.readCount == 1)
  }

  /// The delay is waited on purpose and sits outside the time from press to
  /// panel, so a slow clock that would leave a press no budget still leaves
  /// the delayed appearance the whole read.
  @Test
  func aDelayedAppearanceReadsWithTheWholeDeadline() async {
    let (presenter, reader, sleep) = delayedFixture(step: .milliseconds(80))
    presenter.handleHotkey(.forward, deliveryDelay: nil)
    sleep.open()
    await settle()

    #expect(reader.readCount == 1)
    #expect(reader.deadlines == [PanelPresenter.badgeReadDeadline])
  }

  // MARK: Private

  private let table = AppBadges(byProcess: [0: .count(3)])

  private func reading(_ outcome: BadgeReading.Outcome) -> BadgeReading {
    BadgeReading(badges: table, outcome: outcome, elapsed: .milliseconds(2))
  }

  private func badgeFixture(
    enabled: Bool = true,
    step: Duration = .microseconds(4800)
  ) -> (Fixture, FakeDockBadgeReader) {
    let fixture = Fixture(entryCount: 4, step: step)
    let reader = FakeDockBadgeReader()
    fixture.presenter.badgeReader = reader
    fixture.presenter.appIconBadges = enabled
    return (fixture, reader)
  }

  private func delayedFixture(
    step: Duration = .microseconds(4800)
  ) -> (PanelPresenter, FakeDockBadgeReader, GatedSleep) {
    let sleep = GatedSleep()
    let presenter = PanelPresenter(
      surface: FakeSurface(),
      store: WindowListStore(fixed: SampleWindows.make(count: 4)),
      now: SteppingClock(step: step).read,
      writeLine: { _ in },
      closesOnCommandRelease: { true },
      commandIsHeld: { true },
      commandWatchInterval: .milliseconds(1),
      keyStatusWatchInterval: .milliseconds(1),
      showDelayMs: 150,
      showDelaySleep: sleep.sleep,
      switcher: FakeWindowSwitcher()
    )
    let reader = FakeDockBadgeReader()
    presenter.badgeReader = reader
    presenter.appIconBadges = true
    return (presenter, reader, sleep)
  }

  private func row(
    _ id: WindowItem.Identifier,
    pid: pid_t,
    minimized: Bool = false,
    hidden: Bool = false
  ) -> WindowItem {
    WindowItem(
      id: id,
      ownerProcessIdentifier: pid,
      appName: pid == 42 ? "Mail" : "Notes",
      bundleIdentifier: nil,
      windowTitle: "Inbox",
      kind: .standard,
      isMinimized: minimized,
      isHidden: hidden,
      icon: NSImage()
    )
  }

  private func letter() -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(kVK_ANSI_S), modifiers: [], isARepeat: false, characters: "s")
  }

}
