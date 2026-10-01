import Foundation
@testable import Lanterna
import Logging
import Testing

// MARK: - LogWindowStateTests

/// The table's rows come from the mirror in order, and the counts under it
/// say how many lines there are and how many are selected.
@MainActor
struct LogWindowStateTests {
  @Test
  func rowsFollowTheMirrorOldestFirst() {
    let entries = LogFixture.entries(count: 3)
    let state = LogWindowState(readEntries: { entries })
    state.reload()
    #expect(state.rows.map(\.entry?.sequence) == [1, 2, 3])
    #expect(state.shownRows.map(\.id) == state.rows.map(\.id))
    #expect(state.entryCount == 3)
  }

  @Test
  func rowIdentityNamesTheLaunchAndTheNumber() {
    let entry = LogFixture.entry(sequence: 7)
    #expect(LogRow(entry: entry).id == "\(LogFixture.launch.stamp)#7")
    #expect(LogRow(separatorFor: LogFixture.launch).isSeparator)
  }

  @Test
  func aMessageWithLineBreaksStaysOnOneRow() {
    let entry = LogFixture.entry(sequence: 1, message: "first\nsecond\r\nthird\rfourth")
    #expect(entry.oneLineMessage == "first⏎second⏎third⏎fourth")
    #expect(LogTable.separatorText(LogFixture.launch) == "This launch · \(LogFixture.launch.stamp)")
  }

  @Test
  func theSelectedCountCountsShownLinesOnly() {
    let entries = LogFixture.entries(count: 4)
    let state = LogWindowState(readEntries: { entries })
    state.reload()
    state.selection = [state.rows[1].id, state.rows[3].id, "elsewhere#9"]
    #expect(state.selectedCount == 2)
    #expect(state.selectedEntries.map(\.sequence) == [2, 4])
  }

  @Test
  func theStatusLineReadsInTheContractWording() {
    #expect(
      LogStatusBar.summary(totalCount: 9, shownCount: 9, selectedCount: 0, isFiltered: false, isLoading: false)
        == "9 entries · 0 selected"
    )
    #expect(
      LogStatusBar.summary(totalCount: 9, shownCount: 2, selectedCount: 1, isFiltered: true, isLoading: false)
        == "Showing 2 of 9 entries · 1 selected"
    )
    #expect(
      LogStatusBar.summary(totalCount: 0, shownCount: 0, selectedCount: 0, isFiltered: false, isLoading: true)
        == "Loading saved logs…"
    )
  }

  @Test
  func reloadingPicksUpNewLines() {
    let feed = LogFeed(LogFixture.entries(count: 2))
    let state = LogWindowState(readEntries: { feed.entries })
    state.reload()
    feed.entries.append(LogFixture.entry(sequence: 3))
    state.reload()
    #expect(state.entryCount == 3)
  }
}

// MARK: - LogFeed

/// A mirror a test can add lines to between reads.
@MainActor
final class LogFeed {

  // MARK: Lifecycle

  init(_ entries: [Diagnostics.LogEntry] = []) {
    self.entries = entries
  }

  // MARK: Internal

  var entries: [Diagnostics.LogEntry]

}

// MARK: - LogFixture

/// Lines for the log window's tests, all from one launch unless asked.
enum LogFixture {
  static let launch = LaunchID(
    startedAt: Date(timeIntervalSince1970: 1_790_744_530.481),
    isCurrent: true,
    timeZone: TimeZone(identifier: "Asia/Tokyo") ?? .gmt
  )

  static func entry(
    sequence: UInt64,
    level: Logger.Level = .info,
    category: LogCategory = .activate,
    message: String? = nil,
    context: [String: ContextValue] = [:],
    launch: LaunchID = LogFixture.launch
  ) -> Diagnostics.LogEntry {
    Diagnostics.LogEntry(
      launch: launch,
      sequence: sequence,
      capturedAt: launch.startedAt.addingTimeInterval(Double(sequence)),
      level: level,
      category: category,
      message: message ?? "line \(sequence)",
      source: "Probe.swift:\(sequence)",
      context: context
    )
  }

  static func entries(count: Int, launch: LaunchID = LogFixture.launch) -> [Diagnostics.LogEntry] {
    (1 ... UInt64(count)).map { entry(sequence: $0, launch: launch) }
  }
}
