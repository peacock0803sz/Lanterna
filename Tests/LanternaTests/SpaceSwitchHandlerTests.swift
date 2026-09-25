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
}

/// Answers one window id for any process, so the handler test stages a
/// frontmost window without a live accessibility connection.
private struct FakeFocusedReading: FocusedWindowReading {
    let windowID: CGWindowID
    func focusedWindowID(of _: pid_t) -> CGWindowID? {
        windowID
    }
}
