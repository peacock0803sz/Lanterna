import Foundation
@testable import Lanterna
import Testing

// MARK: - LogWindowScopeTests

/// All launches lays the saved launches out in order. Lines the mirror
/// dropped are not read back: past the row cap the newest lines alone
/// show, and a gap writes no warning.
@MainActor
struct LogWindowScopeTests {

  // MARK: Internal

  /// Past the mirror's cap, only the newest lines show; the dropped ones
  /// are not read back from the file.
  @Test
  func pastTheCapOnlyTheNewestLinesShow() {
    let saved = FakeSavedLogs()
    let total = DiagnosticLog.capacity + 100
    let feed = LogFeed((1 ... UInt64(total)).map { LogFixture.entry(sequence: $0) })
    let state = Self.state(over: feed, saved: saved)
    state.ingest()
    #expect(state.entryCount == DiagnosticLog.capacity)
    #expect(state.currentRows.compactMap(\.entry?.sequence).min() == UInt64(total - DiagnosticLog.capacity + 1))
  }

  /// A jump in the numbers is left alone and no warning is written.
  @Test
  func aJumpInTheNumbersIsLeftAloneWithNoWarning() {
    let saved = FakeSavedLogs()
    let lines = LineSink()
    let feed = LogFeed((6 ... 10).map { LogFixture.entry(sequence: $0) })
    let state = Self.state(over: feed, saved: saved, lines: lines)
    state.ingest()
    #expect(state.entryCount == 5)
    #expect(lines.lines.isEmpty)
  }

  /// Paused past the cap, resuming shows the newest waiting lines.
  @Test
  func resumingPastTheCapShowsTheNewestWaitingLines() {
    let saved = FakeSavedLogs()
    let feed = LogFeed(LogFixture.entries(count: 2))
    let state = Self.state(over: feed, saved: saved)
    state.ingest()
    state.pause()
    let total = DiagnosticLog.capacity + 2
    feed.entries = (3 ... UInt64(total)).map { LogFixture.entry(sequence: $0) }
    state.ingest()
    #expect(state.entryCount == 2)
    state.resume()
    #expect(state.entryCount == DiagnosticLog.capacity)
    #expect(state.currentRows.compactMap(\.entry?.sequence).max() == UInt64(total))
  }

  /// All launches opens each launch with its separator, the older ones
  /// first, and this launch last.
  @Test
  func allLaunchesPutsASeparatorAtEachLaunch() async {
    let saved = FakeSavedLogs()
    saved.others = [
      SavedLaunchEntries(launch: Self.earlier, entries: LogFixture.entries(count: 2, launch: Self.earlier))
    ]
    let feed = LogFeed(LogFixture.entries(count: 1))
    let state = Self.state(over: feed, saved: saved)
    state.ingest()
    state.scope = .allLaunches
    #expect(state.isLoading)
    await state.olderTask?.value
    #expect(!state.isLoading)
    #expect(state.rows.map(\.id) == [
      "\(Self.earlier.stamp)#0",
      "\(Self.earlier.stamp)#1",
      "\(Self.earlier.stamp)#2",
      "\(LogFixture.launch.stamp)#0",
      "\(LogFixture.launch.stamp)#1",
    ])
    #expect(state.entryCount == 3)
    state.scope = .thisLaunch
    #expect(state.rows.count == 1)
  }

  /// Copies and exports name each line's own launch.
  @Test
  func copiesNameEachLinesLaunch() async {
    let saved = FakeSavedLogs()
    saved.others = [SavedLaunchEntries(launch: Self.earlier, entries: [LogFixture.entry(sequence: 9, launch: Self.earlier)])]
    let state = Self.state(over: LogFeed(LogFixture.entries(count: 1)), saved: saved)
    state.ingest()
    state.scope = .allLaunches
    await state.olderTask?.value
    let text = LogExport.copyText(state.copyTargets)
    let lines = text.split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines[0].hasPrefix("\(Self.earlier.stamp) #9 "))
    #expect(lines[1].hasPrefix("\(LogFixture.launch.stamp) #1 "))
    #expect(LogExport.jsonLines(state.shownEntries).contains(#""launch":"\#(Self.earlier.stamp)""#))
  }

  /// Skipped lines are reported once per read.
  @Test
  func skippedLinesAreReportedOncePerRead() async {
    let saved = FakeSavedLogs()
    saved.others = []
    saved.skipped = 3
    let lines = LineSink()
    let state = Self.state(over: LogFeed(), saved: saved, lines: lines)
    state.scope = .allLaunches
    await state.olderTask?.value
    #expect(lines.lines.count == 1)
    #expect(lines.lines.first?.category == .logs)
  }

  // MARK: Private

  private static let earlier = LaunchID(
    startedAt: LogFixture.launch.startedAt.addingTimeInterval(-3600),
    isCurrent: false,
    timeZone: TimeZone(identifier: "Asia/Tokyo") ?? .gmt
  )

  private static func state(over feed: LogFeed, saved: FakeSavedLogs, lines: LineSink = LineSink()) -> LogWindowState {
    LogWindowState(
      entriesAfter: { after in feed.entries.filter { $0.sequence > after } },
      currentLaunch: LogFixture.launch,
      savedLogs: saved.source,
      writeLine: { lines.lines.append($0) },
      liveInterval: .seconds(3600)
    )
  }

}

// MARK: - FakeSavedLogs

/// Saved launches held in memory.
// swiftlint:disable:next no_unchecked_sendable - Every mutable state below is set by the test between reads
final class FakeSavedLogs: @unchecked Sendable {

  var others = [SavedLaunchEntries]()
  var skipped = 0
  var isSaving = true

  var source: SavedLogSource {
    SavedLogSource(
      currentFile: { [self] in isSaving ? URL(fileURLWithPath: "/tmp/current.jsonl") : nil },
      readOthers: { [self] _ in
        SavedLaunchBatch(launches: others, skippedLines: skipped, unreadableFiles: 0)
      }
    )
  }

}

// MARK: - LineSink

/// Keeps the lines the log window writes about itself.
@MainActor
final class LineSink {
  var lines = [LogLine]()
}
