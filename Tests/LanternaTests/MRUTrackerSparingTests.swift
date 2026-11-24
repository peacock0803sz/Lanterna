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
/// list without being closed, so its use is kept for the pass that finds it
/// again. The clock steps past the sweep grace period on every read.
@MainActor
struct MRUTrackerSparingTests {

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
  /// left missing keeps its use through the appearance that sweeps.
  @Test
  func anAppearanceSparesTheWindowsItsPassLeftMissing() async {
    let clock = SteppingClock(step: .seconds(4))
    let tracker = MRUTracker(now: clock.read)
    let elsewhere = sparingRow(windowID: 1, owner: 101)
    let other = sparingRow(windowID: 2, owner: 102)
    tracker.record(elsewhere.id, ownerProcessIdentifier: 101, origin: .external)
    // Gathered after the use, so the use is not kept for being newer than
    // the snapshot.
    let gatheredAt = clock.read()
    let store = WindowListStore(
      gather: {
        WindowListSnapshot(
          items: [other],
          applicationCount: 2,
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
    let presenter = PanelPresenter(surface: FakeSurface(), store: store, writeLine: { _ in }, tracker: tracker)
    presenter.handleHotkey(.forward, deliveryDelay: nil)

    #expect(tracker.arranged([other, elsewhere]).map(\.id) == [elsewhere.id, other.id])
  }

}
