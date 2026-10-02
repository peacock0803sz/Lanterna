import AppKit
@testable import Lanterna
import Synchronization
import Testing

// MARK: - RecordingSpaceLocator

/// Records every batch it is asked about and the thread it was asked on,
/// then answers from a fixed set. A `Mutex` because it is asked from a
/// worker thread.
private final class RecordingSpaceLocator: SpaceLocating {

  // MARK: Lifecycle

  init(onOtherSpace: Set<CGWindowID> = []) {
    self.onOtherSpace = onOtherSpace
  }

  // MARK: Internal

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

  // MARK: Private

  private struct Record {
    var batches = [[CGWindowID]]()
    var mainThreadCalls = 0
  }

  private let onOtherSpace: Set<CGWindowID>
  private let record = Mutex(Record())

}

// MARK: - WindowEnumeratorSpaceTests

/// The locator's answer has to reach the rows, and the question has to be
/// asked the way the refresh budget allows: once per pass, off the main
/// thread, about every window the pass found.
@MainActor
struct WindowEnumeratorSpaceTests {

  // MARK: Internal

  @Test
  func rowsTheLocatorNamesAreOnAnotherSpace() {
    let enumerator = WindowEnumerator(
      reader: FakeReader(reads),
      locator: FakeSpaceLocator(onOtherSpace: [11, 20])
    )
    let snapshot = enumerator.enumerate(applications: applications, startedAt: .now)
    #expect(snapshot.items.map(\.isOnOtherSpace) == [false, true, true])
  }

  @Test
  func rowsTheLocatorNamesAsFullscreenReadFullscreen() {
    let enumerator = WindowEnumerator(
      reader: FakeReader(reads),
      locator: FakeSpaceLocator(fullscreen: [11])
    )
    let snapshot = enumerator.enumerate(applications: applications, startedAt: .now)
    #expect(snapshot.items.map(\.isFullscreen) == [false, true, false])
  }

  @Test
  func anAXFullscreenFlagSurvivesALocatorThatKnowsNothing() {
    let axReads: [pid_t: Result<ApplicationRead, ReadFailure>] = [
      100: read([record(10, isFullscreen: true)])
    ]
    let enumerator = WindowEnumerator(
      reader: FakeReader(axReads),
      locator: FakeSpaceLocator()
    )
    let snapshot = enumerator.enumerate(applications: [application(100)], startedAt: .now)
    #expect(snapshot.items.map(\.isFullscreen) == [true])
  }

  /// A locator that knows nothing leaves every row in view.
  @Test
  func anEmptyAnswerLeavesEveryRowInView() {
    let enumerator = WindowEnumerator(reader: FakeReader(reads), locator: FakeSpaceLocator())
    let snapshot = enumerator.enumerate(applications: applications, startedAt: .now)
    #expect(snapshot.items.allSatisfy { !$0.isOnOtherSpace })
  }

  /// One question per pass, naming every window read and nothing from an
  /// application that failed.
  @Test
  func thePassAsksOnceAboutEveryWindowItRead() {
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
  @Test
  func theSpaceQueryRunsAwayFromTheMainThread() async {
    let locator = RecordingSpaceLocator()
    _ = await WindowEnumerator(reader: FakeReader(reads), locator: locator).enumerateOffMainThread(
      applications: applications,
      startedAt: .now
    )
    #expect(locator.batches.count == 1)
    #expect(locator.mainThreadCalls == 0)
  }

  @Test
  func theOffMainPathCarriesTheFlagToo() async {
    let enumerator = WindowEnumerator(
      reader: FakeReader(reads),
      locator: RecordingSpaceLocator(onOtherSpace: [10])
    )
    let snapshot = await enumerator.enumerateOffMainThread(applications: applications, startedAt: .now)
    #expect(snapshot.items.map(\.isOnOtherSpace) == [true, false, false])
  }

  /// The summary counts the rows placed elsewhere, so a manual check can
  /// see the detection working without reading any row.
  @Test
  func theSummaryCountsRowsOnOtherSpaces() {
    let enumerator = WindowEnumerator(
      reader: FakeReader(reads),
      locator: FakeSpaceLocator(onOtherSpace: [11, 20])
    )
    let snapshot = enumerator.enumerate(applications: applications, startedAt: .now)
    #expect(snapshot.summaryLine.contains("; 2 on other Spaces"))
  }

  /// Each window carries the group of the Space it is on, named after the
  /// desktop and, with several displays, the display; a window the server
  /// says nothing about joins the first shown Space.
  @Test
  func rowsCarryTheGroupOfTheirSpace() {
    let layout = SpaceLayout(displays: [
      SpaceLayout.Display(
        identifier: "MAIN",
        spaces: [.init(id: 1, isFullscreen: false, desktopNumber: 1), .init(id: 2, isFullscreen: false, desktopNumber: 2)],
        current: 1
      ),
      SpaceLayout.Display(identifier: "SIDE", spaces: [.init(id: 5, isFullscreen: false, desktopNumber: 1)], current: 5),
    ])
    let enumerator = WindowEnumerator(
      reader: FakeReader(reads),
      locator: FakeSpaceLocator(spaces: [10: [2], 20: [5]], layout: layout),
      displayNames: { ["MAIN": "Studio Display"] }
    )
    let groups = enumerator.enumerate(applications: applications, startedAt: .now).items.map(\.spaceGroup)
    #expect(groups == [
      SpaceGroup(order: 2, title: "Desktop 2", detail: "Studio Display"),
      SpaceGroup(order: 0, title: "Desktop 1", detail: "Studio Display · shown"),
      SpaceGroup(order: 1, title: "Desktop 1", detail: "Display 2 · shown"),
    ])
  }

  /// Without the displays' Spaces there is no group to join.
  @Test
  func noLayoutLeavesRowsUngrouped() {
    let enumerator = WindowEnumerator(reader: FakeReader(reads), locator: FakeSpaceLocator())
    let snapshot = enumerator.enumerate(applications: applications, startedAt: .now)
    #expect(snapshot.items.allSatisfy { $0.spaceGroup == nil })
  }

  // MARK: Private

  private let applications = [application(100), application(200, name: "Mail")]
  private let reads: [pid_t: Result<ApplicationRead, ReadFailure>] = [
    100: read([record(10), record(11)]),
    200: read([record(20)]),
  ]

}
