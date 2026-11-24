import AppKit
@testable import Lanterna
import Testing

/// Builds the row these tests sort. Local because the sibling suites keep
/// their own builders private.
@MainActor
private func sparingRow(windowID: CGWindowID, owner: pid_t) -> WindowItem {
  WindowItem(
    id: WindowItem.Identifier(windowID: windowID),
    ownerProcessIdentifier: owner,
    appName: "SameApp",
    bundleIdentifier: nil,
    windowTitle: "Same Title",
    kind: .standard,
    isMinimized: false,
    icon: NSImage(size: NSSize(width: 1, height: 1))
  )
}

// MARK: - MRUTrackerSparingTests

/// A window on a hidden Space the read could not reach is absent from the
/// list, which says nothing about whether it closed, so its use is kept for
/// the pass that finds it again. The clock steps past the sweep grace period
/// on every read.
@MainActor
struct MRUTrackerSparingTests {

  // MARK: Internal

  @Test
  func aSparedRecordOutlivesItsWindowsAbsence() {
    let tracker = MRUTracker(now: SteppingClock(step: .seconds(4)).read)
    let elsewhere = sparingRow(windowID: 1, owner: 101)
    let other = sparingRow(windowID: 2, owner: 102)
    tracker.record(elsewhere.id, ownerProcessIdentifier: 101, origin: .external)

    _ = tracker.ordered([other], sparingRecords: [MRUKey(id: elsewhere.id, ownerProcessIdentifier: 101)])

    #expect(tracker.ordered([other, elsewhere]).map(\.id) == [elsewhere.id, other.id])
  }

  @Test
  func aRecordNotSparedIsSweptAsBefore() {
    let tracker = MRUTracker(now: SteppingClock(step: .seconds(4)).read)
    let elsewhere = sparingRow(windowID: 1, owner: 101)
    let other = sparingRow(windowID: 2, owner: 102)
    tracker.record(elsewhere.id, ownerProcessIdentifier: 101, origin: .external)

    _ = tracker.ordered([other])

    #expect(tracker.ordered([other, elsewhere]).map(\.id) == [other.id, elsewhere.id])
  }

  /// The panel hands the sweep what its snapshot spares: a window the pass
  /// left missing keeps its use through the appearance that sweeps. A use
  /// the pass does not spare is swept, which shows the sweep ran.
  @Test
  func anAppearanceSparesTheWindowsItsPassLeftMissing() async {
    let clock = SteppingClock(step: .seconds(4))
    let tracker = MRUTracker(now: clock.read)
    tracker.record(elsewhere.id, ownerProcessIdentifier: 101, origin: .external)
    tracker.record(gone.id, ownerProcessIdentifier: 103, origin: .external)
    // Gathered after the uses, so neither is kept for being newer than the
    // snapshot.
    let store = await storeLeavingElsewhereMissing(gatheredAt: clock.read())
    let presenter = presenter(over: store, tracker: tracker)
    presenter.handleHotkey(.forward, deliveryDelay: nil)

    #expect(tracker.recordCount == 1)
    #expect(tracker.arranged([gone, elsewhere]).map(\.id) == [elsewhere.id, gone.id])
  }

  /// A release that beats the show delay commits without showing, and
  /// that way out hands the sweep the same spared records. The commit
  /// writes its own row's use beside the one spared.
  @Test
  func aCommitWithoutShowingSparesTheWindowsItsPassLeftMissing() async {
    let clock = SteppingClock(step: .seconds(4))
    let tracker = MRUTracker(now: clock.read)
    tracker.record(elsewhere.id, ownerProcessIdentifier: 101, origin: .external)
    tracker.record(gone.id, ownerProcessIdentifier: 103, origin: .external)
    let store = await storeLeavingElsewhereMissing(gatheredAt: clock.read())
    let switcher = FakeWindowSwitcher()
    let presenter = presenter(over: store, tracker: tracker, showDelayMs: 150, switcher: switcher)
    presenter.handleHotkey(.forward, deliveryDelay: nil)
    presenter.handleCommandRelease()

    #expect(switcher.targets.count == 1)
    #expect(tracker.recordCount == 2)
    #expect(tracker.arranged([gone, elsewhere]).map(\.id) == [elsewhere.id, gone.id])
  }

  // MARK: Private

  /// Left missing on a hidden Space by the pass.
  private var elsewhere: WindowItem {
    sparingRow(windowID: 1, owner: 101)
  }

  /// Neither listed nor spared: gone as far as the pass can tell.
  private var gone: WindowItem {
    sparingRow(windowID: 3, owner: 103)
  }

  private var listed: [WindowItem] {
    [sparingRow(windowID: 2, owner: 102), sparingRow(windowID: 4, owner: 104)]
  }

  /// A store whose pass lists `listed` and leaves `elsewhere` missing.
  private func storeLeavingElsewhereMissing(gatheredAt: ContinuousClock.Instant) async -> WindowListStore {
    let listed = listed
    let store = WindowListStore(
      gather: {
        WindowListSnapshot(
          items: listed,
          applicationCount: 3,
          gatheringDuration: .milliseconds(12),
          skipped: [],
          droppedWithoutID: 0,
          gatheredAt: gatheredAt,
          missingOtherSpaceWindows: [.init(name: "SameApp", processIdentifier: 101, windowIDs: [1])]
        )
      },
      writeLine: { _ in }
    )
    await store.refresh()
    return store
  }

  /// A presenter held by Command, with a switcher that only records, so
  /// nothing here reads the keyboard or brings an application forward.
  private func presenter(
    over store: WindowListStore,
    tracker: MRUTracker,
    showDelayMs: Double? = nil,
    switcher: FakeWindowSwitcher = FakeWindowSwitcher()
  ) -> PanelPresenter {
    PanelPresenter(
      surface: FakeSurface(),
      store: store,
      ownProcessIdentifier: ownProcess,
      writeLine: { _ in },
      closesOnCommandRelease: { true },
      commandIsHeld: { true },
      showDelayMs: showDelayMs,
      showDelaySleep: GatedSleep().sleep,
      switcher: switcher,
      tracker: tracker
    )
  }

}
