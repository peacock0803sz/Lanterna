@testable import Lanterna
import Testing

// MARK: - GatedSleep

/// A sleep the test opens by hand, so the wait can be staged around it:
/// presses and releases land while the delay is still shut, and the
/// firing happens only when the test says so.
@MainActor
final class GatedSleep {

  // MARK: Internal

  private(set) var waits = 0

  func sleep(_: Duration) async {
    waits += 1
    if opened {
      return
    }
    await withCheckedContinuation { resumes.append($0) }
  }

  func open() {
    opened = true
    let waiting = resumes
    resumes = []
    for resume in waiting {
      resume.resume()
    }
  }

  // MARK: Private

  private var opened = false
  private var resumes = [CheckedContinuation<Void, Never>]()

}

// MARK: - PanelPresenterShowDelayTests

/// The show delay seen from the presenter: what a release finds waiting,
/// what repeated presses do to the wait, and what firing leaves behind.
@MainActor
struct PanelPresenterShowDelayTests {

  // MARK: Internal

  /// A release that beats the wait still switches: the row is taken
  /// without anything ever appearing.
  @Test
  func aReleaseDuringTheWaitCommitsWithoutShowing() async throws {
    let fixture = waitingFixture()
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.handleCommandRelease()
    await settle()

    #expect(fixture.surface.presentedLists.isEmpty)
    #expect(fixture.surface.dismissCount == 0)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("panel shown") }))
    #expect(fixture.switcher.targets.count == 1)
    let taken = try #require(fixture.switcher.targets.first)
    #expect(taken.id == fixture.windows[1].id)
    #expect(fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  /// Letting go costs no waiting: the commit is already done while the
  /// delay is still shut.
  @Test
  func aReleaseDoesNotWaitForTheDelay() {
    let fixture = waitingFixture()
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.handleCommandRelease()

    #expect(fixture.switcher.targets.count == 1)
    #expect(!fixture.presenter.pendingShow.isWaiting)
  }

  /// A release with no list yet has nothing to take: the press is called
  /// off the way a press waiting for its first list is.
  @Test
  func aReleaseWithoutAListCallsThePressOff() async {
    let fake = HeldGather(entryCount: 4)
    let fixture = waitingFixture(
      store: WindowListStore(gather: fake.gather, writeLine: { _ in })
    )
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    await fake.waitUntilCalled()
    fixture.presenter.handleCommandRelease()

    fake.finish()
    await settle()

    #expect(fixture.surface.presentedLists.isEmpty)
    #expect(fixture.surface.dismissCount == 0)
    #expect(fixture.switcher.targets.isEmpty)
    #expect(
      fixture.log.lines == [
        "press called off 4.8 ms after Command was released, "
          + "before the panel appeared"
      ]
    )
  }

  /// Presses landing inside the wait move the choice along and start the
  /// wait over, so a burst opens one panel on the row it walked to.
  @Test
  func repeatPressesRestartTheWaitAndAccumulate() async {
    let fixture = waitingFixture()
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    await settle()
    fixture.sleep.open()
    await settle()

    #expect(fixture.sleep.waits == 2)
    #expect(fixture.surface.presentedLists.count == 1)
    #expect(fixture.presenter.selection.chosenID == fixture.windows[2].id)
  }

  /// Once the wait has fired, a release is an ordinary commit of the
  /// panel on screen.
  @Test
  func aFiredWaitTreatsAReleaseAsAnOrdinaryCommit() async {
    let fixture = waitingFixture()
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    await settle()
    fixture.sleep.open()
    await settle()
    fixture.presenter.handleCommandRelease()
    await settle()

    #expect(fixture.surface.presentedLists.count == 1)
    #expect(fixture.surface.dismissCount == 1)
    #expect(!fixture.surface.isPresented)
    #expect(fixture.log.lines.contains(where: { $0.hasPrefix("panel shown") }))
    #expect(fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  /// The frontmost application moving on while the wait is shut takes
  /// the waiting press with it: nothing appears for it.
  @Test
  func anActivationChangeDuringTheWaitCallsItOff() async {
    let fixture = waitingFixture()
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.handleActivation(of: otherProcess)
    fixture.sleep.open()
    await settle()

    #expect(fixture.surface.presentedLists.isEmpty)
    #expect(fixture.switcher.targets.isEmpty)
    #expect(
      fixture.log.lines.contains(where: { $0.contains("called off the press") })
    )
  }

  /// Presses in mixed directions replay in arrival order: the same
  /// presses in different orders land on different rows.
  @Test
  func mixedPressesReplayInArrivalOrder() async {
    let forward = waitingFixture()
    forward.presenter.handleHotkey(.forward, deliveryDelay: nil)
    forward.presenter.handleHotkey(.forward, deliveryDelay: nil)
    forward.presenter.handleHotkey(.forward, deliveryDelay: nil)
    await settle()
    forward.sleep.open()
    await settle()

    let backward = waitingFixture()
    backward.presenter.handleHotkey(.forward, deliveryDelay: nil)
    backward.presenter.handleHotkey(.reverse, deliveryDelay: nil)
    backward.presenter.handleHotkey(.forward, deliveryDelay: nil)
    await settle()
    backward.sleep.open()
    await settle()

    #expect(forward.surface.presentedLists.count == 1)
    #expect(backward.surface.presentedLists.count == 1)
    #expect(forward.presenter.selection.chosenID == forward.windows[3].id)
    #expect(backward.presenter.selection.chosenID == backward.windows[1].id)
  }

  /// With the delay off, a press still puts the panel up at once.
  @Test
  func theOffPathShowsImmediately() {
    let surface = FakeSurface()
    let log = DiagnosticsLog()
    let presenter = PanelPresenter(
      surface: surface,
      store: WindowListStore(fixed: SampleWindows.make(count: 4)),
      ownProcessIdentifier: ownProcess,
      now: SteppingClock(step: .microseconds(4800)).read,
      writeLine: log.write,
      closesOnCommandRelease: { true },
      commandIsHeld: { true },
      commandWatchInterval: .milliseconds(1),
      keyStatusWatchInterval: .milliseconds(1),
      switcher: FakeWindowSwitcher()
    )
    presenter.handleHotkey(.forward, deliveryDelay: nil)

    #expect(surface.presentedLists.count == 1)
  }

  // MARK: Private

  /// A presenter with the delay on and its sleep held shut by the test.
  private func waitingFixture(
    store: WindowListStore? = nil
  ) -> (
    presenter: PanelPresenter,
    surface: FakeSurface,
    log: DiagnosticsLog,
    windows: [WindowItem],
    switcher: FakeWindowSwitcher,
    sleep: GatedSleep
  ) {
    let windows = SampleWindows.make(count: 4)
    let surface = FakeSurface()
    let log = DiagnosticsLog()
    let switcher = FakeWindowSwitcher()
    let sleep = GatedSleep()
    let presenter = PanelPresenter(
      surface: surface,
      store: store ?? WindowListStore(fixed: windows),
      ownProcessIdentifier: ownProcess,
      now: SteppingClock(step: .microseconds(4800)).read,
      writeLine: log.write,
      closesOnCommandRelease: { true },
      commandIsHeld: { true },
      commandWatchInterval: .milliseconds(1),
      keyStatusWatchInterval: .milliseconds(1),
      showDelayMs: 150,
      showDelaySleep: sleep.sleep,
      switcher: switcher
    )
    return (presenter, surface, log, windows, switcher, sleep)
  }

}
