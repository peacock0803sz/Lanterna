import AppKit
@testable import Lanterna
import Testing

/// Builds the row the tracker sorts, with nothing the sort does not read.
///
/// Titles repeat on purpose: two rows sharing both names is what FR-008 is
/// about, and a sort that told them apart by name would pass every case that
/// gave them different ones.
@MainActor
private func row(windowID: CGWindowID, owner: pid_t) -> WindowItem {
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

/// The ordering contract, held without any window server.
///
/// Every case here runs against injected records only (FR-017): which row is
/// newest is decided by the test, never by watching real activations. The
/// live observation behind the records was settled before implementation in
/// the spike the plan put first.
@MainActor
struct MRUTrackerTests {
    private let first = row(windowID: 1, owner: 101)
    private let second = row(windowID: 2, owner: 102)
    private let third = row(windowID: 3, owner: 103)

    /// A commit names the row it took, and the next appearance draws that
    /// row first. One record moving one row is the whole of FR-001; a path
    /// that recorded nothing would leave the order it found.
    @Test func commitPutsTheTargetFirst() {
        let tracker = MRUTracker()
        tracker.record(
            second.id, ownerProcessIdentifier: second.ownerProcessIdentifier,
            origin: .commit
        )
        tracker.record(
            first.id, ownerProcessIdentifier: first.ownerProcessIdentifier,
            origin: .commit
        )
        #expect(tracker.ordered([first, second, third]).map(\.id) == [first.id, second.id, third.id])
        #expect(tracker.newestSource == .commit)
    }

    /// Three uses in order read back in reverse, with no other row between
    /// them. The count matters: a sort that kept relative order would pass a
    /// single record and fail three.
    @Test func threeUsesReadBackNewestFirst() {
        let tracker = MRUTracker()
        for item in [first, second, third] {
            tracker.record(
                item.id, ownerProcessIdentifier: item.ownerProcessIdentifier,
                origin: .commit
            )
        }
        #expect(tracker.ordered([first, second, third]).map(\.id) == [third.id, second.id, first.id])
    }

    /// The row an external activation names beats an older commit. Newest
    /// wins whatever the kind; kinds only decide the `via` word, never the
    /// order.
    @Test func externalRecordBeatsOlderCommit() {
        let tracker = MRUTracker()
        tracker.record(
            first.id, ownerProcessIdentifier: first.ownerProcessIdentifier,
            origin: .commit
        )
        tracker.record(
            second.id, ownerProcessIdentifier: second.ownerProcessIdentifier,
            origin: .external
        )
        #expect(tracker.ordered([first, second, third]).map(\.id) == [second.id, first.id, third.id])
        #expect(tracker.newestSource == .external)
    }

    /// The second row of the sorted list is the previously recorded target,
    /// which is what the panel's initial choice reads. The choice itself
    /// belongs to the selection; what belongs here is that the data puts the
    /// right row second.
    @Test func secondRowIsThePreviouslyRecordedTarget() {
        let tracker = MRUTracker()
        tracker.record(
            second.id, ownerProcessIdentifier: second.ownerProcessIdentifier,
            origin: .commit
        )
        tracker.record(
            first.id, ownerProcessIdentifier: first.ownerProcessIdentifier,
            origin: .commit
        )
        #expect(tracker.ordered([first, second, third])[1].id == second.id)
    }

    /// Rows with no record keep the input order behind every recorded row.
    /// The input arrives in the store's fixed order, so "no record" and
    /// "fixed order" are the same thing from this side.
    @Test func unrecordedRowsStayLastInInputOrder() {
        let tracker = MRUTracker()
        tracker.record(
            second.id, ownerProcessIdentifier: second.ownerProcessIdentifier,
            origin: .commit
        )
        #expect(tracker.ordered([first, second, third]).map(\.id) == [second.id, first.id, third.id])
    }

    /// One row and none are not cases of their own: one row is first, and
    /// nothing listed means nothing recorded.
    @Test func singleRowAndEmptyLists() {
        let tracker = MRUTracker()
        #expect(tracker.ordered([first]).map(\.id) == [first.id])
        #expect(tracker.ordered([]).isEmpty)
        #expect(tracker.newestSource == .none)
    }

    /// Records for windows that are gone go at show time, and only then.
    /// Sweeping anywhere else would delete a record the next appearance
    /// still needs; never sweeping would grow the records without bound.
    @Test func missingRecordsArePrunedAtShowTime() {
        let tracker = MRUTracker()
        tracker.record(
            first.id, ownerProcessIdentifier: first.ownerProcessIdentifier,
            origin: .commit
        )
        tracker.record(
            second.id, ownerProcessIdentifier: second.ownerProcessIdentifier,
            origin: .external
        )
        #expect(tracker.ordered([first]).map(\.id) == [first.id])
        #expect(tracker.newestSource == .commit)
    }

    /// Pruning the newest record must not strand the `via` word: it falls
    /// back to the surviving newest record's origin, or to none when nothing
    /// survives. The origin rides on each record for exactly this reason.
    @Test func viaFallsBackToSurvivingNewestAfterPrune() {
        let tracker = MRUTracker()
        tracker.record(
            first.id, ownerProcessIdentifier: first.ownerProcessIdentifier,
            origin: .commit
        )
        tracker.record(
            second.id, ownerProcessIdentifier: second.ownerProcessIdentifier,
            origin: .external
        )
        _ = tracker.ordered([first])
        #expect(tracker.newestSource == .commit)
        _ = tracker.ordered([third])
        #expect(tracker.newestSource == .none)
    }

    /// Two rows sharing both names stay two rows, told apart by identity
    /// alone. Recording the second puts the second first — never the other
    /// one with the same words on it.
    @Test func duplicateNamesStayDistinctByIdentity() {
        let tracker = MRUTracker()
        tracker.record(
            second.id, ownerProcessIdentifier: second.ownerProcessIdentifier,
            origin: .commit
        )
        let ordered = tracker.ordered([first, second])
        #expect(ordered.first?.id == second.id)
        #expect(ordered.map(\.id).count == 2)
    }

    /// A window id outlives neither its window nor, on reuse, its process:
    /// the key is the pair, so a reused id under another owner does not merge
    /// with the dead record. Ten hundred dead records behind forty live rows
    /// still sort inside the charter's bound, which is what keeps the sweep
    /// inside the show span.
    @Test func reusedIDUnderAnotherOwnerDoesNotMerge() {
        let tracker = MRUTracker()
        let reborn = row(windowID: 1, owner: 999)
        tracker.record(first.id, ownerProcessIdentifier: 101, origin: .commit)
        tracker.record(reborn.id, ownerProcessIdentifier: 999, origin: .external)
        let ordered = tracker.ordered([reborn])
        #expect(ordered.map(\.id) == [reborn.id])
        #expect(tracker.newestSource == .external)
    }

    @Test func thousandStaleRecordsStillSortInsideTheBound() {
        let tracker = MRUTracker()
        for index in 0 ..< 1000 {
            tracker.record(
                WindowItem.Identifier(windowID: CGWindowID(10000 + index)),
                ownerProcessIdentifier: pid_t(5000 + index),
                origin: .commit
            )
        }
        let live = (0 ..< 40).map { row(windowID: CGWindowID(100 + $0), owner: pid_t(200 + $0)) }
        let startedAt = ContinuousClock.now
        let ordered = tracker.ordered(live)
        let elapsed = ContinuousClock.now - startedAt
        #expect(ordered.count == 40)
        #expect(elapsed < .milliseconds(100))
    }
}

/// A commit through the presenter writes the record with the commit kind,
/// before anything is taken. The tracker behind the panel is the same one
/// the ordering reads: one memory, not two.
@MainActor
struct MRUCommitWiringTests {
    @Test func commitThroughThePresenterRecordsWithCommitKind() {
        let fixture = Fixture(entryCount: 3, closesOnCommandRelease: true)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        fixture.presenter.handleCommandRelease()
        #expect(fixture.presenter.tracker.newestSource == .commit)
    }
}

/// The seam through which activations from outside the panel arrive.
///
/// The reader names the frontmost window or fails; the entry records it or
/// does nothing. Both halves are injected here because no test can switch
/// applications for real, and the live observation behind them was settled
/// before implementation in the spike the plan put first.
@MainActor
struct MRUExternalSeamTests {
    private struct FakeFocusedReader: FocusedWindowReading {
        var windowID: CGWindowID?
        func focusedWindowID(of _: pid_t) -> CGWindowID? {
            windowID
        }
    }

    @Test func reportedWindowIDIsRecordedAsExternal() {
        let tracker = MRUTracker()
        recordExternalActivation(
            of: 102, excluding: 101,
            reading: FakeFocusedReader(windowID: 2), into: tracker
        )
        #expect(tracker.newestSource == .external)
    }

    @Test func failedReadRecordsNothing() {
        let tracker = MRUTracker()
        recordExternalActivation(
            of: 102, excluding: 101,
            reading: FakeFocusedReader(windowID: nil), into: tracker
        )
        #expect(tracker.newestSource == .none)
    }

    @Test func ownProcessRecordsNothing() {
        let tracker = MRUTracker()
        recordExternalActivation(
            of: 101, excluding: 101,
            reading: FakeFocusedReader(windowID: 1), into: tracker
        )
        #expect(tracker.newestSource == .none)
    }

    @Test func liveReaderReportsTheFocusedWindowID() {
        let reader = AXFocusedWindowReader(
            setMessagingTimeout: { _, _ in .success },
            copyFocusedWindow: { _ in (.success, AXUIElementCreateApplication(102)) },
            copyWindowID: { _ in (.success, 7) }
        )
        #expect(reader.focusedWindowID(of: 102) == 7)
    }

    @Test func liveReaderFailuresReadAsNothing() {
        #expect(
            AXFocusedWindowReader(
                setMessagingTimeout: { _, _ in .failure },
                copyFocusedWindow: { _ in (.success, AXUIElementCreateApplication(102)) },
                copyWindowID: { _ in (.success, 7) }
            ).focusedWindowID(of: 102) == nil
        )
        #expect(
            AXFocusedWindowReader(
                setMessagingTimeout: { _, _ in .success },
                copyFocusedWindow: { _ in (.cannotComplete, nil) },
                copyWindowID: { _ in (.success, 7) }
            ).focusedWindowID(of: 102) == nil
        )
        #expect(
            AXFocusedWindowReader(
                setMessagingTimeout: { _, _ in .success },
                copyFocusedWindow: { _ in (.success, AXUIElementCreateApplication(102)) },
                copyWindowID: { _ in (.failure, 0) }
            ).focusedWindowID(of: 102) == nil
        )
        #expect(
            AXFocusedWindowReader(
                setMessagingTimeout: { _, _ in .success },
                copyFocusedWindow: { _ in (.success, AXUIElementCreateApplication(102)) },
                copyWindowID: { _ in (.success, 0) }
            ).focusedWindowID(of: 102) == nil
        )
    }
}

/// An appearance keeps the list it was given: recording while it is up
/// changes the next appearance, never the one on screen. The tracker always
/// answers from current records, so the freeze lives in the presenter
/// holding its array, and this pins the model half — a returned order is a
/// value, already detached from later writes.
@MainActor
struct MRUShownListFreezeTests {
    @Test func returnedOrderIsDetachedFromLaterRecords() {
        let tracker = MRUTracker()
        let first = row(windowID: 1, owner: 101)
        let second = row(windowID: 2, owner: 102)
        tracker.record(
            first.id, ownerProcessIdentifier: first.ownerProcessIdentifier,
            origin: .commit
        )
        let shown = tracker.ordered([first, second])
        tracker.record(
            second.id, ownerProcessIdentifier: second.ownerProcessIdentifier,
            origin: .external
        )
        #expect(shown.map(\.id) == [first.id, second.id])
        #expect(tracker.ordered([first, second]).map(\.id) == [second.id, first.id])
    }
}
