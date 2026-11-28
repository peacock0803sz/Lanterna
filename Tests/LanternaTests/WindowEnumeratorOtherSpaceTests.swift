import AppKit
import Testing
@testable import Lanterna

/// How a pass hands each application what the window server keeps of it on
/// hidden Spaces, and whether it is hidden.
@MainActor
struct WindowEnumeratorOtherSpaceTests {

  // MARK: Internal

  /// With the setting on, the window server is asked once per pass, and
  /// each application is handed its own windows from the answer.
  @Test
  func eachApplicationIsHandedItsOwnWindowsElsewhere() {
    let reader = FakeReader([:])
    var locator = FakeSpaceLocator()
    locator.otherSpace = OtherSpaceWindows(windows: [1: [10, 11], 2: [20]])

    _ = WindowEnumerator(reader: reader, locator: locator, readsOtherSpaces: true)
      .enumerate(applications: [application(1), application(2, name: "Safari"), application(3, name: "Mail")], startedAt: .now)

    #expect(locator.calls.otherSpaceReads == 1)
    #expect(reader.calls.byProcess[1]?.otherSpaceWindows == [10, 11])
    #expect(reader.calls.byProcess[2]?.otherSpaceWindows == [20])
    #expect(reader.calls.byProcess[3]?.otherSpaceWindows == [])
  }

  /// With the setting off the window server is not asked, and no
  /// application is handed anything to look for.
  @Test
  func theSettingOffNeverAsksForWindowsElsewhere() {
    let reader = FakeReader([:])
    var locator = FakeSpaceLocator()
    locator.otherSpace = OtherSpaceWindows(windows: [1: [10]])

    _ = WindowEnumerator(reader: reader, locator: locator)
      .enumerate(applications: [application(1)], startedAt: .now)

    #expect(locator.calls.otherSpaceReads == 0)
    #expect(reader.calls.byProcess[1]?.otherSpaceWindows == [])
  }

  /// Whether an application is hidden is read with its name, on the main
  /// thread, and handed to its read.
  @Test
  func eachApplicationIsToldWhetherItIsHidden() {
    let reader = FakeReader([:])

    _ = WindowEnumerator(reader: reader, locator: FakeSpaceLocator(), readsOtherSpaces: true)
      .enumerate(applications: [application(1, isHidden: true), application(2, name: "Safari")], startedAt: .now)

    #expect(reader.calls.byProcess[1]?.isHidden == true)
    #expect(reader.calls.byProcess[2]?.isHidden == false)
  }

  /// Windows a read could not settle are kept on the snapshot by
  /// application, in process order, named the way the panel names it.
  @Test
  func windowsLeftMissingAreKeptByApplication() {
    let reader = FakeReader([
      1: .success(ApplicationRead(records: [], droppedWithoutID: 0, missingOtherSpaceWindows: [10, 11])),
      2: .success(ApplicationRead(records: [record(20)], droppedWithoutID: 0)),
      3: .success(ApplicationRead(records: [record(30)], droppedWithoutID: 0, missingOtherSpaceWindows: [31])),
      4: .failure(.timedOut),
    ])

    let snapshot = WindowEnumerator(reader: reader, locator: FakeSpaceLocator(), readsOtherSpaces: true)
      .enumerate(
        applications: [
          application(3, name: "Mail"),
          application(1, name: "Preview"),
          application(2, name: "Safari"),
          application(4, name: "Notes"),
        ],
        startedAt: .now
      )

    #expect(snapshot.missingOtherSpaceWindows.map(\.name) == ["Preview", "Mail"])
    #expect(snapshot.missingOtherSpaceWindows.map(\.processIdentifier) == [1, 3])
    #expect(snapshot.missingOtherSpaceWindows.map(\.windowIDs) == [[10, 11], [31]])
  }

  /// An application whose windows elsewhere could not be read, and that
  /// has no window row, is listed as one row standing for them rather than
  /// as an application with no window.
  @Test
  func anApplicationWithOnlyUnreadWindowsElsewhereGetsAStandIn() {
    let row = standIn(for: ApplicationRead(records: [], droppedWithoutID: 0, missingOtherSpaceWindows: [10, 11]))

    #expect(row?.id == .application(1))
    #expect(row?.windowsElsewhere == 2)
    #expect(row?.isOnOtherSpace == true)
    #expect(row?.windowTitle == "")
    #expect(row?.standsForWindowsElsewhere == true)
  }

  /// An application that answers both its main and its focused window with
  /// an explicit "no value" keeps only a closed window elsewhere, as far as
  /// can be told: it is an application with no window, as without the
  /// setting, and the snapshot still records the window as not found.
  @Test
  func anApplicationNamingNoWindowGetsNoStandIn() {
    let snapshot = WindowEnumerator(
      reader: FakeReader([
        1: .success(ApplicationRead(records: [], droppedWithoutID: 0, missingOtherSpaceWindows: [10], namesNoWindow: true))
      ]),
      locator: FakeSpaceLocator(),
      readsOtherSpaces: true
    ).enumerate(applications: [application(1, name: "Preview")], startedAt: .now)

    #expect(snapshot.items.map(\.id) == [.application(1)])
    #expect(snapshot.items.first?.standsForWindowsElsewhere == false)
    #expect(snapshot.items.first?.isWindowless == true)
    #expect(snapshot.missingOtherSpaceWindows.map(\.windowIDs) == [[10]])
  }

  /// A window dropped for want of an id leaves no row of its own, so it
  /// must not keep the stand-in away either, or the application vanishes.
  @Test
  func aDroppedWindowDoesNotKeepTheStandInAway() {
    let row = standIn(for: ApplicationRead(records: [], droppedWithoutID: 1, missingOtherSpaceWindows: [10]))
    #expect(row?.windowsElsewhere == 1)
  }

  /// A look cut short leaves its unjudged windows missing, and they still
  /// stand in.
  @Test
  func aCutShortLookStillGetsAStandIn() {
    let row = standIn(for: ApplicationRead(
      records: [],
      droppedWithoutID: 0,
      otherSpacesCutShort: true,
      missingOtherSpaceWindows: [10]
    ))
    #expect(row?.windowsElsewhere == 1)
  }

  /// With nothing missing, the rows are what they were: an application with
  /// no window gets its row, and one whose only window was dropped gets none.
  @Test
  func nothingMissingLeavesTheRowsAsTheyWere() {
    let snapshot = WindowEnumerator(
      reader: FakeReader([
        1: .success(ApplicationRead(records: [], droppedWithoutID: 0)),
        2: .success(ApplicationRead(records: [], droppedWithoutID: 1)),
      ]),
      locator: FakeSpaceLocator(),
      readsOtherSpaces: true
    ).enumerate(applications: [application(1), application(2, name: "Safari")], startedAt: .now)

    #expect(snapshot.items.map(\.id) == [.application(1)])
    #expect(snapshot.items.first?.isWindowless == true)
  }

  /// An application with a window row keeps that row, and its windows left
  /// missing are only recorded, never a second row.
  @Test
  func anApplicationWithAWindowRowGetsNoStandIn() {
    let snapshot = WindowEnumerator(
      reader: FakeReader([1: .success(ApplicationRead(
        records: [record(20)],
        droppedWithoutID: 0,
        missingOtherSpaceWindows: [10]
      ))]),
      locator: FakeSpaceLocator(),
      readsOtherSpaces: true
    ).enumerate(applications: [application(1)], startedAt: .now)

    #expect(snapshot.items.map(\.id) == [.window(20)])
  }

  /// The stand-in is fullscreen only when every window it stands for is.
  @Test
  func theStandInIsFullscreenOnlyWhenAllItsWindowsAre() {
    let read = ApplicationRead(records: [], droppedWithoutID: 0, missingOtherSpaceWindows: [10, 11])
    var all = FakeSpaceLocator()
    all.fullscreen = [10, 11]
    var some = FakeSpaceLocator()
    some.fullscreen = [10]

    #expect(standIn(for: read, locator: all)?.isFullscreen == true)
    #expect(standIn(for: read, locator: some)?.isFullscreen == false)
  }

  /// The stand-in joins the group of the first, in drawing order, of the
  /// Spaces its windows are on, read with the rest of the pass's windows.
  @Test
  func theStandInJoinsTheFirstGroupOfItsWindows() {
    let layout = SpaceLayout(displays: [
      SpaceLayout.Display(
        identifier: "MAIN",
        spaces: [
          .init(id: 1, isFullscreen: false, desktopNumber: 1),
          .init(id: 2, isFullscreen: false, desktopNumber: 2),
          .init(id: 3, isFullscreen: false, desktopNumber: 3),
        ],
        current: 1
      )
    ])
    let locator = FakeSpaceLocator(spaces: [10: [3], 11: [2]], layout: layout)
    let read = ApplicationRead(records: [], droppedWithoutID: 0, missingOtherSpaceWindows: [10, 11])

    let row = standIn(for: read, locator: locator)

    #expect(row?.spaceGroup?.title == "Desktop 2")
    #expect(Set(locator.calls.readings.last ?? []) == [10, 11])
  }

  /// A hidden application's stand-in is a hidden application's row.
  @Test
  func aHiddenApplicationsStandInIsHidden() {
    let row = standIn(
      for: ApplicationRead(records: [], droppedWithoutID: 0, missingOtherSpaceWindows: [10]),
      isHidden: true
    )
    #expect(row?.isHidden == true)
  }

  /// A stand-in is counted among the rows on other Spaces as one row, not
  /// as the windows it stands for.
  @Test
  func aStandInCountsAsOneRowOnOtherSpaces() {
    let snapshot = WindowEnumerator(
      reader: FakeReader([1: .success(ApplicationRead(
        records: [],
        droppedWithoutID: 0,
        missingOtherSpaceWindows: [10, 11]
      ))]),
      locator: FakeSpaceLocator(),
      readsOtherSpaces: true
    ).enumerate(applications: [application(1, name: "Preview")], startedAt: .now)

    #expect(snapshot.summaryLine.contains("; 1 on other Spaces"))
    #expect(snapshot.summaryLine.hasSuffix("; not found on other Spaces: Preview (2)"))
  }

  /// The off-main-thread path hands over the same arguments.
  @Test
  func theOffMainThreadPassHandsOverTheSame() async {
    let reader = FakeReader([:])
    var locator = FakeSpaceLocator()
    locator.otherSpace = OtherSpaceWindows(windows: [1: [10]])

    _ = await WindowEnumerator(reader: reader, locator: locator, readsOtherSpaces: true)
      .enumerateOffMainThread(applications: [application(1, isHidden: true)], startedAt: .now)

    #expect(reader.calls.byProcess[1] == ReadCalls.Call(otherSpaceWindows: [10], isHidden: true))
  }

  // MARK: Private

  /// The one row a pass makes for application 1 answering `read`.
  private func standIn(
    for read: ApplicationRead,
    locator: FakeSpaceLocator = FakeSpaceLocator(),
    isHidden: Bool = false
  ) -> WindowItem? {
    let snapshot = WindowEnumerator(reader: FakeReader([1: .success(read)]), locator: locator, readsOtherSpaces: true)
      .enumerate(applications: [application(1, name: "Preview", isHidden: isHidden)], startedAt: .now)
    #expect(snapshot.items.count == 1)
    return snapshot.items.first
  }

}
