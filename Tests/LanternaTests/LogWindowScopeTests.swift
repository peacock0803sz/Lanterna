import Foundation
@testable import Lanterna
import Synchronization
import Testing

// MARK: - LogWindowScopeTests

/// Lines the mirror dropped come back from this launch's file, and All
/// launches lays the saved launches out in order.
@MainActor
struct LogWindowScopeTests {

  // MARK: Internal

  /// Past the mirror's cap right after launch, the first lines are read
  /// from the file and the numbers run without a gap.
  @Test
  func theLinesFromBeforeTheCapComeBackFromTheFile() async {
    let saved = FakeSavedLogs(current: LogFixture.entries(count: 600))
    let feed = LogFeed((101 ... 600).map { LogFixture.entry(sequence: $0) })
    let state = Self.state(over: feed, saved: saved)
    state.setVisible(true)
    await state.fillTask?.value
    #expect(state.rows.map(\.entry?.sequence) == (1 ... 600).map { Optional($0) })
    #expect(state.filledRanges == [1 ... 100])
    state.setVisible(false)
  }

  /// Closed after reading, then 600 lines later reopened: the middle is
  /// filled from the file.
  @Test
  func aGapWhileTheWindowWasClosedIsFilled() async {
    let saved = FakeSavedLogs(current: LogFixture.entries(count: 3))
    let feed = LogFeed(LogFixture.entries(count: 3))
    let state = Self.state(over: feed, saved: saved)
    state.setVisible(true)
    state.setVisible(false)
    saved.current = LogFixture.entries(count: 603)
    feed.entries = (104 ... 603).map { LogFixture.entry(sequence: $0) }
    state.setVisible(true)
    await state.fillTask?.value
    #expect(state.entryCount == 603)
    #expect(zip(state.rows, state.rows.dropFirst()).allSatisfy { ($0.entry?.sequence ?? 0) + 1 == $1.entry?.sequence })
    state.setVisible(false)
  }

  /// With nothing being saved, the gap is left alone and no warning is
  /// written.
  @Test
  func nothingSavedMeansNoFillAndNoWarning() async {
    let saved = FakeSavedLogs(current: LogFixture.entries(count: 10))
    saved.isSaving = false
    let lines = LineSink()
    let feed = LogFeed((6 ... 10).map { LogFixture.entry(sequence: $0) })
    let state = Self.state(over: feed, saved: saved, lines: lines)
    state.ingest()
    await state.fillTask?.value
    #expect(state.entryCount == 5)
    #expect(saved.currentReads.withLock { $0 } == 0)
    #expect(lines.lines.isEmpty)
  }

  /// Paused past the cap, resuming shows every line in order.
  @Test
  func resumingAfterAGapWhilePausedShowsEveryLine() async {
    let saved = FakeSavedLogs(current: LogFixture.entries(count: 2))
    let feed = LogFeed(LogFixture.entries(count: 2))
    let state = Self.state(over: feed, saved: saved)
    state.ingest()
    state.pause()
    saved.current = LogFixture.entries(count: 602)
    feed.entries = (103 ... 602).map { LogFixture.entry(sequence: $0) }
    state.ingest()
    await state.fillTask?.value
    #expect(state.entryCount == 2)
    state.resume()
    #expect(state.rows.map(\.entry?.sequence) == (1 ... 602).map { Optional($0) })
  }

  /// All launches opens each launch with its separator, the older ones
  /// first, and this launch last.
  @Test
  func allLaunchesPutsASeparatorAtEachLaunch() async {
    let saved = FakeSavedLogs(current: [])
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
    let saved = FakeSavedLogs(current: [])
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
    let saved = FakeSavedLogs(current: [])
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

  // MARK: Lifecycle

  init(current: [Diagnostics.LogEntry]) {
    self.current = current
  }

  // MARK: Internal

  var current: [Diagnostics.LogEntry]
  var others = [SavedLaunchEntries]()
  var skipped = 0
  var isSaving = true
  let currentReads = Mutex(0)

  var source: SavedLogSource {
    SavedLogSource(
      currentFile: { [self] in isSaving ? URL(fileURLWithPath: "/tmp/current.jsonl") : nil },
      readCurrent: { [self] _, _ in
        currentReads.withLock { $0 += 1 }
        return SavedLaunchRead(entries: current, skippedLines: 0, isReadable: true)
      },
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
