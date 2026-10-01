@testable import Lanterna
import Testing

/// New lines join the list as they arrive; pausing holds the list still
/// while they wait, and resuming shows exactly what waited.
@MainActor
struct LogWindowLiveTests {

  // MARK: Internal

  @Test
  func eachLookTakesOnlyTheNewLines() {
    let feed = LogFeed(LogFixture.entries(count: 2))
    let state = Self.state(over: feed)
    state.ingest()
    feed.entries.append(LogFixture.entry(sequence: 3))
    state.ingest()
    #expect(state.rows.map(\.entry?.sequence) == [1, 2, 3])
    #expect(state.lastSequence == 3)
  }

  @Test
  func pausingHoldsTheListWhileLinesWait() {
    let feed = LogFeed(LogFixture.entries(count: 2))
    let state = Self.state(over: feed)
    state.ingest()
    state.pause()
    feed.entries.append(contentsOf: [LogFixture.entry(sequence: 3), LogFixture.entry(sequence: 4)])
    state.ingest()
    #expect(state.shownRows.count == 2)
    #expect(state.entryCount == 2)
    #expect(state.pendingCount == 2)
  }

  /// Lines that leave the mirror while paused still show on resume, and
  /// the list grows by exactly the waiting count.
  @Test
  func resumingShowsWhatWaitedEvenOnceTheMirrorDroppedIt() {
    let feed = LogFeed(LogFixture.entries(count: 2))
    let state = Self.state(over: feed)
    state.ingest()
    state.pause()
    feed.entries.append(contentsOf: [LogFixture.entry(sequence: 3), LogFixture.entry(sequence: 4)])
    state.ingest()
    let waiting = state.pendingCount
    feed.entries.removeFirst(3)
    state.resume()
    #expect(state.entryCount == 2 + waiting)
    #expect(state.rows.map(\.entry?.sequence) == [1, 2, 3, 4])
    #expect(state.pendingRows.isEmpty)
    #expect(!state.isPaused)
  }

  /// A jump in the numbers with nothing saved is let go: there is no
  /// file to fill it from.
  @Test
  func aJumpInTheNumbersWithNothingSavedIsLetGo() {
    let feed = LogFeed((5 ... 7).map { LogFixture.entry(sequence: $0) })
    let state = Self.state(over: feed)
    state.ingest()
    #expect(state.missingRanges.isEmpty)
    #expect(state.filledRanges.isEmpty)
    #expect(state.rows.map(\.entry?.sequence) == [5, 6, 7])
  }

  @Test
  func theLiveLabelSaysHowManyWait() {
    #expect(LiveIndicator.text(isPaused: false, pendingCount: 4) == "Live")
    #expect(LiveIndicator.text(isPaused: true, pendingCount: 3) == "Paused · 3 new matching entries waiting")
  }

  @Test
  func comingOnScreenTakesInWhatArrivedMeanwhile() {
    let feed = LogFeed(LogFixture.entries(count: 3))
    let state = Self.state(over: feed)
    #expect(state.rows.isEmpty)
    state.setVisible(true)
    #expect(state.entryCount == 3)
    state.setVisible(false)
    #expect(state.liveTask == nil)
  }

  // MARK: Private

  /// Polls far less often than any test runs, so only the explicit looks
  /// take lines in.
  private static func state(over feed: LogFeed) -> LogWindowState {
    LogWindowState(
      entriesAfter: { after in feed.entries.filter { $0.sequence > after } },
      liveInterval: .seconds(3600)
    )
  }

}
