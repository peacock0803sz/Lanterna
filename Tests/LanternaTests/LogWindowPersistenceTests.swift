import AppKit
@testable import Lanterna
import Testing

/// The filters, the scope and the columns outlive the window: closing and
/// opening it again finds them as they were.
@MainActor
struct LogWindowPersistenceTests {
  @Test
  func reopeningKeepsTheFiltersScopeAndColumns() {
    let saved = FakeSavedLogs()
    let state = LogWindowState(entriesAfter: { _ in [] }, savedLogs: saved.source, writeLine: { _ in })
    let guides = GuideWindows(logState: state)
    let window = guides.logWindow()
    state.searchText = "timed out"
    state.levelFloor = .warning
    state.category = .activate
    state.scope = .allLaunches
    state.setShown(.source, true)
    state.setShownContext("app", true)
    window.close()
    let reopened = guides.logWindow()
    #expect(reopened === window)
    #expect(guides.logState.searchText == "timed out")
    #expect(guides.logState.levelFloor == .warning)
    #expect(guides.logState.category == .activate)
    #expect(guides.logState.scope == .allLaunches)
    #expect(guides.logState.isShown(.source))
    #expect(guides.logState.contextColumns == ["app"])
  }

  @Test
  func savingOffKeepsTheScopeOnThisLaunch() {
    let saved = FakeSavedLogs()
    let state = LogWindowState(entriesAfter: { _ in [] }, savedLogs: saved.source, writeLine: { _ in })
    state.scope = .allLaunches
    state.setSavingEnabled(false)
    #expect(state.scope == .thisLaunch)
    state.scope = .allLaunches
    #expect(state.scope == .thisLaunch)
    state.setSavingEnabled(true)
    state.scope = .allLaunches
    #expect(state.scope == .allLaunches)
  }
}
