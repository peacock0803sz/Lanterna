@testable import Lanterna
import Testing

/// Choosing the table's columns: the defaults, the hidden fixed ones, the
/// context keys, the last column that cannot go, and the way back.
@MainActor
struct LogWindowColumnsTests {

  // MARK: Internal

  @Test
  func aFreshWindowShowsTheFiveDefaultColumns() {
    let state = Self.state()
    #expect(LogColumn.allCases.filter(state.isShown) == [.sequence, .time, .level, .category, .message])
    #expect(state.shownColumnCount == 5)
  }

  @Test
  func theLaunchAndSourceColumnsCanBeAdded() {
    let state = Self.state()
    state.setShown(.launch, true)
    state.setShown(.source, true)
    #expect(state.isShown(.launch))
    #expect(state.isShown(.source))
    #expect(state.shownColumnCount == 7)
  }

  @Test
  func contextKeysComeFromTheLinesInRangeInNameOrder() {
    let state = Self.state()
    #expect(state.availableContextKeys == ["app", "ms", "pid", "result"])
  }

  @Test
  func aChosenKeyStaysWhenTheLinesNoLongerCarryIt() {
    let feed = LogFeed(Self.entries)
    let state = LogWindowState(entriesAfter: { after in feed.entries.filter { $0.sequence > after } })
    state.ingest()
    state.setShownContext("app", true)
    state.setShownContext("ms", true)
    #expect(state.contextColumns == ["app", "ms"])
    state.category = .config
    state.scope = .allLaunches
    state.scope = .thisLaunch
    #expect(state.contextColumns == ["app", "ms"])
    let bare = LogWindowState(readEntries: { [LogFixture.entry(sequence: 1)] })
    bare.ingest()
    bare.setShownContext("window", true)
    #expect(bare.availableContextKeys == ["window"])
  }

  @Test
  func theLastColumnCannotBeTakenAway() {
    let state = Self.state()
    for column in [LogColumn.sequence, .time, .level, .category] {
      state.setShown(column, false)
    }
    #expect(state.shownColumnCount == 1)
    #expect(!state.canHide(.message))
    state.setShown(.message, false)
    #expect(state.isShown(.message))
    state.setShownContext("app", true)
    state.setShown(.message, false)
    #expect(!state.isShown(.message))
    state.setShownContext("app", false)
    #expect(state.contextColumns == ["app"])
  }

  @Test
  func resettingGoesBackToTheDefaults() {
    let state = Self.state()
    state.setShown(.launch, true)
    state.setShown(.time, false)
    state.setShownContext("pid", true)
    state.resetColumns()
    #expect(LogColumn.allCases.filter(state.isShown) == [.sequence, .time, .level, .category, .message])
    #expect(state.contextColumns.isEmpty)
  }

  @Test
  func theColumnTitlesMatchTheMenu() {
    #expect(LogColumn.allCases.map(\.title) == ["Launch", "#", "Time", "Level", "Category", "Message", "Source"])
  }

  // MARK: Private

  private static let entries = [
    LogFixture.entry(sequence: 1, context: ["app": .string("Vivaldi"), "pid": .int(8123)]),
    LogFixture.entry(sequence: 2, category: .panel, context: ["ms": .int(31)]),
    LogFixture.entry(sequence: 3, context: ["result": .string("ok"), "app": .string("Safari")]),
  ]

  private static func state() -> LogWindowState {
    let state = LogWindowState(readEntries: { entries })
    state.ingest()
    return state
  }

}
