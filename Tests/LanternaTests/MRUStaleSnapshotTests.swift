import AppKit
@testable import Lanterna
import Testing

/// Builds the row the stale-snapshot tests sort. Local because the sibling
/// suites keep their own builders private, and sharing one would couple
/// the files.
@MainActor
private func staleRow(windowID: CGWindowID, owner: pid_t) -> WindowItem {
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

/// A record newer than the swept snapshot survives it, however stale the
/// look: the snapshot finished before the use happened, so absence proves
/// nothing. A snapshot that could have seen it sweeps normally.
@MainActor
struct MRUStaleSnapshotTests {
    @Test func snapshotTooOldToKnowSparesTheRecord() {
        let clock = SteppingClock(step: .seconds(4))
        let tracker = MRUTracker(now: clock.read)
        let target = staleRow(windowID: 1, owner: 101)
        let other = staleRow(windowID: 2, owner: 102)
        let before = clock.read()
        tracker.record(
            target.id, ownerProcessIdentifier: target.ownerProcessIdentifier,
            origin: .external
        )
        tracker.noteSnapshotObserved(before)
        #expect(tracker.ordered([other]).map(\.id) == [other.id])
        #expect(tracker.newestSource == .external)
        tracker.noteSnapshotObserved(clock.read())
        _ = tracker.ordered([other])
        #expect(tracker.newestSource == .none)
    }
}
