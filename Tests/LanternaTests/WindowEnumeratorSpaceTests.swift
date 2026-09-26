import AppKit
@testable import Lanterna
import Synchronization
import Testing

/// Records every batch it is asked about and the thread it was asked on,
/// then answers from a fixed set. A `Mutex` because it is asked from a
/// worker thread.
private final class RecordingSpaceLocator: SpaceLocating {
    private struct Record {
        var batches: [[CGWindowID]] = []
        var mainThreadCalls = 0
    }

    private let onOtherSpace: Set<CGWindowID>
    private let record = Mutex(Record())

    init(onOtherSpace: Set<CGWindowID> = []) {
        self.onOtherSpace = onOtherSpace
    }

    var batches: [[CGWindowID]] {
        record.withLock { $0.batches }
    }

    var mainThreadCalls: Int {
        record.withLock { $0.mainThreadCalls }
    }

    func windowsOnOtherSpaces(among windowIDs: [CGWindowID]) -> Set<CGWindowID> {
        record.withLock {
            $0.batches.append(windowIDs)
            if Thread.isMainThread {
                $0.mainThreadCalls += 1
            }
        }
        return onOtherSpace.intersection(windowIDs)
    }
}

/// The locator's answer has to reach the rows, and the question has to be
/// asked the way the refresh budget allows: once per pass, off the main
/// thread, about every window the pass found.
@MainActor
struct WindowEnumeratorSpaceTests {
    private let applications = [application(100), application(200, name: "Mail")]
    private let reads: [pid_t: Result<ApplicationRead, ReadFailure>] = [
        100: read([record(10), record(11)]),
        200: read([record(20)]),
    ]

    @Test func rowsTheLocatorNamesAreOnAnotherSpace() {
        let enumerator = WindowEnumerator(
            reader: FakeReader(reads),
            locator: FakeSpaceLocator(onOtherSpace: [11, 20])
        )
        let snapshot = enumerator.enumerate(applications: applications, startedAt: .now)
        #expect(snapshot.items.map(\.isOnOtherSpace) == [false, true, true])
    }

    @Test func rowsTheLocatorNamesAsFullscreenReadFullscreen() {
        let enumerator = WindowEnumerator(
            reader: FakeReader(reads),
            locator: FakeSpaceLocator(fullscreen: [11])
        )
        let snapshot = enumerator.enumerate(applications: applications, startedAt: .now)
        #expect(snapshot.items.map(\.isFullscreen) == [false, true, false])
    }

    @Test func anAXFullscreenFlagSurvivesALocatorThatKnowsNothing() {
        let axReads: [pid_t: Result<ApplicationRead, ReadFailure>] = [
            100: read([record(10, isFullscreen: true)]),
        ]
        let enumerator = WindowEnumerator(
            reader: FakeReader(axReads),
            locator: FakeSpaceLocator()
        )
        let snapshot = enumerator.enumerate(applications: [application(100)], startedAt: .now)
        #expect(snapshot.items.map(\.isFullscreen) == [true])
    }

    /// A locator that knows nothing leaves every row in view.
    @Test func anEmptyAnswerLeavesEveryRowInView() {
        let enumerator = WindowEnumerator(reader: FakeReader(reads), locator: FakeSpaceLocator())
        let snapshot = enumerator.enumerate(applications: applications, startedAt: .now)
        #expect(snapshot.items.allSatisfy { !$0.isOnOtherSpace })
    }

    /// One question per pass, naming every window read and nothing from an
    /// application that failed.
    @Test func thePassAsksOnceAboutEveryWindowItRead() {
        let locator = RecordingSpaceLocator()
        var reads = reads
        reads[300] = .failure(.timedOut)
        _ = WindowEnumerator(reader: FakeReader(reads), locator: locator).enumerate(
            applications: applications + [application(300, name: "TextEdit")],
            startedAt: .now
        )
        #expect(locator.batches.count == 1)
        #expect(locator.batches.first.map(Set.init) == [10, 11, 20])
    }

    /// The window-server calls block like the reading does, so they belong
    /// on the same side of the thread boundary.
    @Test func theSpaceQueryRunsAwayFromTheMainThread() async {
        let locator = RecordingSpaceLocator()
        _ = await WindowEnumerator(reader: FakeReader(reads), locator: locator).enumerateOffMainThread(
            applications: applications,
            startedAt: .now
        )
        #expect(locator.batches.count == 1)
        #expect(locator.mainThreadCalls == 0)
    }

    @Test func theOffMainPathCarriesTheFlagToo() async {
        let enumerator = WindowEnumerator(
            reader: FakeReader(reads),
            locator: RecordingSpaceLocator(onOtherSpace: [10])
        )
        let snapshot = await enumerator.enumerateOffMainThread(applications: applications, startedAt: .now)
        #expect(snapshot.items.map(\.isOnOtherSpace) == [true, false, false])
    }

    /// The summary counts the rows placed elsewhere, so a manual check can
    /// see the detection working without reading any row.
    @Test func theSummaryCountsRowsOnOtherSpaces() {
        let enumerator = WindowEnumerator(
            reader: FakeReader(reads),
            locator: FakeSpaceLocator(onOtherSpace: [11, 20])
        )
        let snapshot = enumerator.enumerate(applications: applications, startedAt: .now)
        #expect(snapshot.summaryLine.contains("; 2 on other Spaces"))
    }
}
