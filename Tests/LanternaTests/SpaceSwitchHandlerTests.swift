import CoreGraphics
import Darwin
@testable import Lanterna
import Testing

/// A Space switch carries no application in its notification, so the handler
/// reads the frontmost application itself and records it the way an
/// activation would, then asks the store for a fresh pass. Without either
/// half the first open after the switch sorts on the pre-switch memory until
/// the next poll pass replaces it (#44).
@MainActor
struct SpaceSwitchHandlerTests {
    @Test func spaceChangeRecordsFrontmostAndRefreshes() async {
        let store = WindowListStore(
            gather: {
                WindowListSnapshot(
                    items: [],
                    applicationCount: 1,
                    gatheringDuration: .milliseconds(1),
                    skipped: [],
                    droppedWithoutID: 0,
                    gatheredAt: .now
                )
            },
            writeLine: { _ in }
        )
        let tracker = MRUTracker()
        let reading = FakeFocusedReading(windowID: 7)
        let log = DiagnosticsLog()
        let handler = SpaceSwitchHandler(
            store: store,
            tracker: tracker,
            ownProcessIdentifier: ownProcess,
            frontmostProcessIdentifier: { otherProcess },
            reading: reading,
            writeLine: log.write
        )

        await handler.handle()

        #expect(store.snapshot != nil)
        #expect(tracker.newestSource == .external)
        #expect(log.lines.contains("space changed; refreshing window list"))
    }

    /// No frontmost application means nothing to record, but the list is
    /// still stale from the switch, so the pass still runs. Both lines are
    /// asserted so the silent branch stays diagnosable.
    @Test func spaceChangeWithoutFrontmostStillRefreshes() async {
        let store = WindowListStore(
            gather: {
                WindowListSnapshot(
                    items: [],
                    applicationCount: 1,
                    gatheringDuration: .milliseconds(1),
                    skipped: [],
                    droppedWithoutID: 0,
                    gatheredAt: .now
                )
            },
            writeLine: { _ in }
        )
        let tracker = MRUTracker()
        let log = DiagnosticsLog()
        let handler = SpaceSwitchHandler(
            store: store,
            tracker: tracker,
            ownProcessIdentifier: ownProcess,
            frontmostProcessIdentifier: { nil },
            reading: FakeFocusedReading(windowID: 7),
            writeLine: log.write
        )

        await handler.handle()

        #expect(tracker.newestSource == .none)
        #expect(store.snapshot != nil)
        #expect(log.lines.contains("space changed; refreshing window list"))
        #expect(log.lines.contains("space changed; no frontmost application to record"))
    }

    /// The switch landed on this process, so there is no external activation
    /// to record, but the list still needs the pass.
    @Test func spaceChangeToOwnProcessStillRefreshes() async {
        let store = WindowListStore(
            gather: {
                WindowListSnapshot(
                    items: [],
                    applicationCount: 1,
                    gatheringDuration: .milliseconds(1),
                    skipped: [],
                    droppedWithoutID: 0,
                    gatheredAt: .now
                )
            },
            writeLine: { _ in }
        )
        let tracker = MRUTracker()
        let log = DiagnosticsLog()
        let handler = SpaceSwitchHandler(
            store: store,
            tracker: tracker,
            ownProcessIdentifier: ownProcess,
            frontmostProcessIdentifier: { ownProcess },
            reading: FakeFocusedReading(windowID: 7),
            writeLine: log.write
        )

        await handler.handle()

        #expect(tracker.newestSource == .none)
        #expect(store.snapshot != nil)
        #expect(log.lines.contains("space changed; frontmost is this process"))
    }

    /// A failed accessibility read records nothing: a failure that recorded
    /// would turn every unreachable application into a use that never
    /// happened. The pass still runs.
    @Test func spaceChangeWithUnreadableFrontmostStillRefreshes() async {
        let store = WindowListStore(
            gather: {
                WindowListSnapshot(
                    items: [],
                    applicationCount: 1,
                    gatheringDuration: .milliseconds(1),
                    skipped: [],
                    droppedWithoutID: 0,
                    gatheredAt: .now
                )
            },
            writeLine: { _ in }
        )
        let tracker = MRUTracker()
        let log = DiagnosticsLog()
        let handler = SpaceSwitchHandler(
            store: store,
            tracker: tracker,
            ownProcessIdentifier: ownProcess,
            frontmostProcessIdentifier: { otherProcess },
            reading: FakeFocusedReading(windowID: nil),
            writeLine: log.write
        )

        await handler.handle()

        #expect(tracker.newestSource == .none)
        #expect(store.snapshot != nil)
        #expect(log.lines.contains("space changed; refreshing window list"))
    }

    /// An update arriving during an in-flight polling pass queues one
    /// following pass instead of being dropped, and handling does not return
    /// until that pass lands (#44). The first pass is held open, the handler
    /// runs inside it, and both passes are then released: two gathers with
    /// two summary lines, the external record kept, and no "skipped" line.
    /// The wait below is event-driven rather than a fixed settle: the record
    /// precedes the queueing in one synchronous segment, so observing the
    /// record means the handler is parked behind the pass.
    @Test(.timeLimit(.minutes(1))) func spaceChangeDuringAPassQueuesAnotherPass() async {
        let fake = HeldGather(entryCount: 5)
        let storeLog = DiagnosticsLog()
        let store = WindowListStore(gather: fake.gather, writeLine: storeLog.write)
        let tracker = MRUTracker()
        let handlerLog = DiagnosticsLog()
        let handler = SpaceSwitchHandler(
            store: store,
            tracker: tracker,
            ownProcessIdentifier: ownProcess,
            frontmostProcessIdentifier: { otherProcess },
            reading: FakeFocusedReading(windowID: 7),
            writeLine: handlerLog.write
        )

        let poll = Task { await store.refreshEventually() }
        await fake.waitUntilCalled()
        let handling = Task { await handler.handle() }
        while tracker.newestSource != .external {
            await Task.yield()
        }
        fake.finish()
        while fake.callCount < 2 {
            await Task.yield()
        }
        fake.finish()
        await handling.value
        await poll.value

        #expect(fake.callCount == 2)
        #expect(store.snapshot?.items.count == 5)
        #expect(storeLog.lines.filter { $0.hasPrefix("listed ") }.count == 2)
        #expect(!storeLog.lines.contains("refresh skipped (previous pass still running)"))
        #expect(tracker.newestSource == .external)
        #expect(handlerLog.lines.contains("space changed; refreshing window list"))
    }
}

/// Answers one window id for any process, so the handler test stages a
/// frontmost window without a live accessibility connection. A nil id stages
/// a failed accessibility read.
private struct FakeFocusedReading: FocusedWindowReading {
    let windowID: CGWindowID?
    func focusedWindowID(of _: pid_t) -> CGWindowID? {
        windowID
    }
}
