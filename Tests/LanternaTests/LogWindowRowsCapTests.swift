import Foundation
@testable import Lanterna
import Testing

/// This launch's rows stop growing: each of the live list and the
/// waiting list holds at most the mirror's capacity, oldest numbers
/// first out, while the saved launches stay untouched.
@MainActor
struct LogWindowRowsCapTests {

  // MARK: Internal

  @Test
  func takingInPastTheCapKeepsTheNewest() {
    let total = DiagnosticLog.capacity + 50
    let feed = LogFeed((1 ... UInt64(total)).map { LogFixture.entry(sequence: $0) })
    let state = Self.state(over: feed)
    state.ingest()
    #expect(state.currentRows.count == DiagnosticLog.capacity)
    #expect(state.rows.count == DiagnosticLog.capacity)
    #expect(state.currentRows
      .map(\.entry?.sequence) == ((UInt64(total - DiagnosticLog.capacity + 1) ... UInt64(total)).map { Optional($0) }))
  }

  @Test
  func pausedLeavesTheShownListAloneAndCapsTheWaiting() {
    let total = DiagnosticLog.capacity * 2
    let feed = LogFeed(LogFixture.entries(count: 10))
    let state = Self.state(over: feed)
    state.ingest()
    state.pause()
    feed.entries.append(contentsOf: (11 ... UInt64(total)).map { LogFixture.entry(sequence: $0) })
    state.ingest()
    #expect(state.currentRows.compactMap(\.entry?.sequence) == Array(1 ... 10))
    #expect(state.rows.count == 10)
    #expect(state.pendingRows.count == DiagnosticLog.capacity)
    let oldestWaiting = state.pendingRows.compactMap(\.entry?.sequence).min()
    #expect(oldestWaiting == UInt64(total - DiagnosticLog.capacity + 1))
  }

  @Test
  func resumingMergesWaitingAndCapsTheWhole() {
    let total = DiagnosticLog.capacity + 20
    let feed = LogFeed(LogFixture.entries(count: 10))
    let state = Self.state(over: feed)
    state.ingest()
    state.pause()
    feed.entries.append(contentsOf: (11 ... UInt64(total)).map { LogFixture.entry(sequence: $0) })
    state.ingest()
    state.resume()
    #expect(state.currentRows.count == DiagnosticLog.capacity)
    #expect(state.rows.count == DiagnosticLog.capacity)
    #expect(state.pendingRows.isEmpty)
    #expect(state.currentRows.last?.entry?.sequence == UInt64(total))
  }

  @Test
  func trimmingDropsTheOldestNumberNotTheArrivalOrder() throws {
    let state = Self.state(over: LogFeed())
    state.currentRows = (1 ... 5).map { LogRow(entry: LogFixture.entry(sequence: $0)) }
      + [LogRow(entry: LogFixture.entry(sequence: 0))]
    state.currentRows += (6 ... UInt64(DiagnosticLog.capacity + 1)).map { LogRow(entry: LogFixture.entry(sequence: $0)) }
    state.rows = state.currentRows
    state.shownRows = state.currentRows
    let evictedID = try #require(state.currentRows.first { $0.entry?.sequence == 0 }?.id)
    let keptID = try #require(state.currentRows.first { $0.entry?.sequence == 2 }?.id)
    state.selection = [evictedID, keptID]
    state.trimCurrentRowsToCapacity()
    #expect(state.currentRows.count == DiagnosticLog.capacity)
    #expect(!state.currentRows.compactMap(\.entry?.sequence).contains(0))
    #expect(state.currentRows.compactMap(\.entry?.sequence).min() == 2)
    #expect(state.rows.count == DiagnosticLog.capacity)
    #expect(state.shownRows.count == DiagnosticLog.capacity)
    #expect(!state.selection.contains(evictedID))
    #expect(state.selection == [keptID])
  }

  @Test
  func allLaunchesKeepsTheSavedRowsWhileCappingThisLaunch() async {
    let earlier = LaunchID(
      startedAt: LogFixture.launch.startedAt.addingTimeInterval(-3600),
      isCurrent: false,
      timeZone: TimeZone(identifier: "Asia/Tokyo") ?? .gmt
    )
    let saved = FakeSavedLogs()
    saved.others = [
      SavedLaunchEntries(launch: earlier, entries: LogFixture.entries(count: 3, launch: earlier))
    ]
    let total = DiagnosticLog.capacity + 30
    let feed = LogFeed((1 ... UInt64(total)).map { LogFixture.entry(sequence: $0) })
    let state = LogWindowState(
      entriesAfter: { after in feed.entries.filter { $0.sequence > after } },
      currentLaunch: LogFixture.launch,
      savedLogs: saved.source,
      liveInterval: .seconds(3600)
    )
    state.ingest()
    state.scope = .allLaunches
    await state.olderTask?.value
    let olderCount = state.olderRows.count
    #expect(olderCount == 4)
    #expect(state.currentRows.count == DiagnosticLog.capacity)
    #expect(state.olderRows.count == olderCount)
    #expect(state.rows.count == olderCount + 1 + DiagnosticLog.capacity)
  }

  // MARK: Private

  private static func state(over feed: LogFeed) -> LogWindowState {
    LogWindowState(
      entriesAfter: { after in feed.entries.filter { $0.sequence > after } },
      liveInterval: .seconds(3600)
    )
  }

}
