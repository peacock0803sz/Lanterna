import Foundation
@testable import Lanterna
import Testing

/// The search text, the level floor and the one category narrow the list,
/// alone and together, and Copy and Export take only what is left.
@MainActor
struct LogWindowFilterTests {

  // MARK: Internal

  @Test
  func theLevelFloorShowsThatLevelAndHeavier() {
    let state = Self.state()
    #expect(state.shownEntryCount == 6)
    state.levelFloor = .warning
    #expect(state.shownEntries.map(\.level) == [.warning, .error, .error])
    state.levelFloor = .error
    #expect(state.shownEntries.map(\.level) == [.error, .error])
    state.levelFloor = .debug
    #expect(state.shownEntryCount == 6)
    #expect(!state.isFiltering)
  }

  @Test
  func oneCategoryShowsOnlyItsLines() {
    let state = Self.state()
    state.category = .activate
    #expect(state.shownEntries.map(\.sequence) == [3, 4, 6])
    #expect(state.isFiltering)
  }

  @Test
  func theSearchIgnoresCase() {
    let state = Self.state()
    state.searchText = "TIMED out"
    #expect(state.shownEntries.map(\.sequence) == [4, 6])
  }

  @Test
  func theThreeCombine() {
    let state = Self.state()
    state.category = .activate
    state.searchText = "timed out"
    state.levelFloor = .error
    #expect(state.shownEntries.map(\.sequence) == [6])
    state.searchText = ""
    state.category = nil
    state.levelFloor = .debug
    #expect(state.shownEntryCount == 6)
  }

  @Test
  func copyAndExportTakeWhatTheFiltersLeave() throws {
    let state = Self.state()
    state.category = .activate
    #expect(state.copyTargets.map(\.sequence) == [3, 4, 6])
    state.selection = [state.rows[0].id, state.rows[3].id]
    #expect(state.copyTargets.map(\.sequence) == [4])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lanterna-filter-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    try state.export(to: url)
    #expect(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count == 3)
  }

  /// The waiting count follows the filters, counted again when they change.
  @Test
  func theWaitingCountFollowsTheFilters() {
    let feed = LogFeed()
    let state = LogWindowState(entriesAfter: { after in feed.entries.filter { $0.sequence > after } })
    state.pause()
    feed.entries = Self.entries
    state.ingest()
    #expect(state.pendingCount == 6)
    state.levelFloor = .error
    #expect(state.pendingCount == 2)
    state.category = .config
    #expect(state.pendingCount == 0)
    state.resume()
    #expect(state.entryCount == 6)
  }

  @Test
  func theFloorsReadInTheContractWording() {
    #expect(LevelFloor.allCases.map(\.title) == ["Debug and above", "Info and above", "Warnings & Errors", "Errors only"])
  }

  // MARK: Private

  private static let entries = [
    LogFixture.entry(sequence: 1, level: .debug, category: .panel, message: "panel shown"),
    LogFixture.entry(sequence: 2, level: .info, category: .config, message: "config loaded"),
    LogFixture.entry(sequence: 3, level: .info, category: .activate, message: "switched to Safari"),
    LogFixture.entry(sequence: 4, level: .warning, category: .activate, message: "could not switch (Timed Out)"),
    LogFixture.entry(sequence: 5, level: .error, category: .hotkey, message: "registered nothing"),
    LogFixture.entry(sequence: 6, level: .error, category: .activate, message: "raise timed out"),
  ]

  private static func state() -> LogWindowState {
    let state = LogWindowState(readEntries: { entries })
    state.ingest()
    return state
  }

}
