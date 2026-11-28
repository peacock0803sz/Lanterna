import AppKit
import Testing
@testable import Lanterna

/// The summary line is what the manual acceptance check greps, so its wording
/// is pinned down here.
@MainActor
struct WindowListSnapshotTests {

  // MARK: Internal

  @Test
  func idsAreUniqueAcrossTheList() {
    #expect(Set(snapshot().items.map(\.id)).count == 9)
  }

  @Test
  func summaryReportsCountsAndDuration() {
    #expect(snapshot().summaryLine == "listed 9 windows from 11 applications in 71.2 ms")
  }

  /// An empty pass is reported in the same words, so the manual acceptance
  /// check's grep finds the line whether or not anything was listed.
  @Test
  func summaryReportsAnEmptyPass() {
    #expect(snapshot(windowCount: 0, applicationCount: 0).summaryLine
      == "listed 0 windows from 0 applications in 71.2 ms")
  }

  @Test
  func summaryStopsAfterTheCountsWhenNothingWentWrong() {
    #expect(!snapshot().summaryLine.contains(";"))
  }

  /// An application missing from the panel is explained by name and reason,
  /// which is how the manual acceptance check tells a wedged application
  /// from a bug.
  @Test
  func summaryNamesEverySkippedApplicationAndWhy() {
    let line = snapshot(skipped: [
      WindowListSnapshot.SkippedApplication(name: "TextEdit", reason: .timedOut, processIdentifier: 101),
      WindowListSnapshot.SkippedApplication(name: "Foo", reason: .permissionMissing, processIdentifier: 102),
      WindowListSnapshot.SkippedApplication(
        name: "Bar",
        reason: .unavailable(.invalidUIElement),
        processIdentifier: 103
      ),
      WindowListSnapshot.SkippedApplication(name: "Baz", reason: .malformedAnswer, processIdentifier: 104),
    ]).summaryLine
    #expect(line.hasSuffix(
      "; skipped TextEdit (timed out), Foo (permission missing), "
        + "Bar (error -25202), Baz (malformed answer)"
    ))
  }

  @Test
  func summaryCountsElementsLostForWantOfAWindowID() {
    #expect(snapshot(droppedWithoutID: 1).summaryLine
      .hasSuffix("; dropped 1 elements without a window id"))
  }

  @Test
  func skippedApplicationsComeBeforeDroppedElements() {
    let line = snapshot(
      skipped: [
        WindowListSnapshot.SkippedApplication(
          name: "TextEdit",
          reason: .timedOut,
          processIdentifier: 101
        )
      ],
      droppedWithoutID: 1
    ).summaryLine
    #expect(line == "listed 9 windows from 11 applications in 71.2 ms"
      + "; skipped TextEdit (timed out)"
      + "; dropped 1 elements without a window id")
  }

  /// Rows on another Space are counted straight after the totals, ahead of
  /// anything that went wrong.
  @Test
  func rowsOnOtherSpacesComeBeforeSkippedApplications() {
    let line = snapshot(
      onOtherSpace: 2,
      skipped: [
        WindowListSnapshot.SkippedApplication(
          name: "TextEdit",
          reason: .timedOut,
          processIdentifier: 101
        )
      ]
    ).summaryLine
    #expect(line == "listed 9 windows from 11 applications in 71.2 ms"
      + "; 2 on other Spaces"
      + "; skipped TextEdit (timed out)")
  }

  /// Applications whose look at other Spaces ended early are counted last,
  /// and only when there are some.
  @Test
  func summaryCountsApplicationsWhoseOtherSpacesWereCutShort() {
    #expect(snapshot(otherSpacesCutShort: 2).summaryLine
      == "listed 9 windows from 11 applications in 71.2 ms"
      + "; other Spaces cut short in 2 applications")
  }

  /// Windows on hidden Spaces a read could not settle are named by
  /// application with a count, in process order, last on the line.
  @Test
  func summaryNamesTheApplicationsWithWindowsElsewhereNotFound() {
    let line = snapshot(missing: [
      WindowListSnapshot.MissingOtherSpace(name: "Preview", processIdentifier: 7, windowIDs: [10, 11]),
      WindowListSnapshot.MissingOtherSpace(name: "Slack", processIdentifier: 9, windowIDs: [20]),
    ]).summaryLine
    #expect(line == "listed 9 windows from 11 applications in 71.2 ms"
      + "; not found on other Spaces: Preview (2), Slack (1)")
  }

  /// The not-found clause comes after the other clauses set here, so the
  /// clauses before it read the same with or without it.
  @Test
  func theNotFoundClauseComesAfterTheOtherClauses() {
    let line = snapshot(
      skipped: [
        WindowListSnapshot.SkippedApplication(name: "TextEdit", reason: .timedOut, processIdentifier: 101)
      ],
      droppedWithoutID: 1,
      otherSpacesCutShort: 1,
      missing: [WindowListSnapshot.MissingOtherSpace(name: "Preview", processIdentifier: 7, windowIDs: [10])]
    ).summaryLine
    #expect(line == "listed 9 windows from 11 applications in 71.2 ms"
      + "; skipped TextEdit (timed out)"
      + "; dropped 1 elements without a window id"
      + "; other Spaces cut short in 1 applications"
      + "; not found on other Spaces: Preview (1)")
  }

  /// The records the recent-use sweep keeps are the windows left missing,
  /// keyed the way the tracker keys a window row.
  @Test
  func sparedRecordsAreTheWindowsLeftMissing() {
    let spared = snapshot(missing: [
      WindowListSnapshot.MissingOtherSpace(name: "Preview", processIdentifier: 7, windowIDs: [10, 11]),
      WindowListSnapshot.MissingOtherSpace(name: "Slack", processIdentifier: 9, windowIDs: [20]),
    ]).sparedRecords
    #expect(spared == [
      MRUKey(id: WindowItem.Identifier(windowID: 10), ownerProcessIdentifier: 7),
      MRUKey(id: WindowItem.Identifier(windowID: 11), ownerProcessIdentifier: 7),
      MRUKey(id: WindowItem.Identifier(windowID: 20), ownerProcessIdentifier: 9),
    ])
  }

  /// The live pass appends this process's own windows by rebuilding the
  /// snapshot, and the summary line and the held list are both read from
  /// the rebuilt one, so windows left missing must survive it.
  @Test
  func appendingOwnWindowsKeepsTheWindowsLeftMissing() {
    let missing = [
      WindowListSnapshot.MissingOtherSpace(name: "Preview", processIdentifier: 7, windowIDs: [10, 11])
    ]
    let base = WindowListSnapshot(
      items: [item(1)],
      applicationCount: 1,
      gatheringDuration: .milliseconds(10),
      skipped: [],
      droppedWithoutID: 0,
      gatheredAt: .now,
      missingOtherSpaceWindows: missing
    )

    #expect(base.includingOwnWindows([item(2)]).missingOtherSpaceWindows == missing)
  }

  /// So must the word that no shown Space could be read, or the line
  /// written after a live pass never says so.
  @Test
  func appendingOwnWindowsKeepsSpacesUnread() {
    let base = WindowListSnapshot(
      items: [item(1)],
      applicationCount: 1,
      gatheringDuration: .milliseconds(10),
      skipped: [],
      droppedWithoutID: 0,
      gatheredAt: .now,
      spacesUnread: true
    )

    let rebuilt = base.includingOwnWindows([item(2)])
    #expect(rebuilt.spacesUnread)
    #expect(rebuilt.summaryLine.contains("; Spaces unread"))
  }

  /// A title never reaches the log, whatever went wrong.
  @Test
  func summaryNeverCarriesAWindowTitle() {
    let line = snapshot(
      skipped: [
        WindowListSnapshot.SkippedApplication(
          name: "TextEdit",
          reason: .timedOut,
          processIdentifier: 101
        )
      ],
      droppedWithoutID: 1
    ).summaryLine
    #expect(!line.contains("Downloads"))
  }

  // MARK: Private

  private func item(_ windowID: CGWindowID, isOnOtherSpace: Bool = false) -> WindowItem {
    WindowItem(
      id: WindowItem.Identifier(windowID: windowID),
      ownerProcessIdentifier: 0,
      appName: "Finder",
      bundleIdentifier: nil,
      windowTitle: "Downloads",
      kind: .standard,
      isMinimized: false,
      isOnOtherSpace: isOnOtherSpace,
      icon: NSImage()
    )
  }

  /// The first `onOtherSpace` of the windows are on another Space.
  private func snapshot(
    windowCount: Int = 9,
    onOtherSpace: Int = 0,
    applicationCount: Int = 11,
    duration: Duration = .milliseconds(71.2),
    skipped: [WindowListSnapshot.SkippedApplication] = [],
    droppedWithoutID: Int = 0,
    otherSpacesCutShort: Int = 0,
    missing: [WindowListSnapshot.MissingOtherSpace] = []
  ) -> WindowListSnapshot {
    WindowListSnapshot(
      items: (0 ..< windowCount).map { item(CGWindowID($0), isOnOtherSpace: $0 < onOtherSpace) },
      applicationCount: applicationCount,
      gatheringDuration: duration,
      skipped: skipped,
      droppedWithoutID: droppedWithoutID,
      gatheredAt: .now,
      otherSpacesCutShort: otherSpacesCutShort,
      missingOtherSpaceWindows: missing
    )
  }

}
