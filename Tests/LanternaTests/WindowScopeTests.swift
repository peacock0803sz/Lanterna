import AppKit
@testable import Lanterna
import Testing

/// One row of the named owner, named so the query decides which match.
@MainActor
private func ownedRow(
  _ windowID: CGWindowID,
  owner: pid_t,
  app: String,
  title: String,
  isMinimized: Bool = false
) -> WindowItem {
  WindowItem(
    id: WindowItem.Identifier(windowID: windowID),
    ownerProcessIdentifier: owner,
    appName: app,
    bundleIdentifier: nil,
    windowTitle: title,
    kind: .standard,
    isMinimized: isMinimized,
    icon: NSImage(size: NSSize(width: 1, height: 1))
  )
}

// MARK: - WindowScopeTests

/// The scope one appearance lists: where it starts, what the key does to
/// it, and how the list and the choice follow.
@MainActor
struct WindowScopeTests {

  // MARK: Internal

  /// Every appearance starts on the setting, over the application that
  /// was in front, whatever the last appearance was switched to.
  @Test
  func anAppearanceStartsOnTheSetting() {
    var scope = ScopeState()
    scope.configured = .frontApp
    scope.begin(target: 42)
    #expect(scope.current == .frontApp)
    #expect(scope.narrowedOwner == 42)
    scope.toggle()
    #expect(scope.current == .allApps)
    #expect(scope.configured == .frontApp)
    scope.begin(target: 7)
    #expect(scope.current == .frontApp)
    #expect(scope.narrowedOwner == 7)
  }

  /// With no application known to be in front, nothing is narrowed.
  @Test
  func anUnknownTargetNarrowsNothing() {
    var scope = ScopeState()
    scope.configured = .frontApp
    scope.begin(target: nil)
    #expect(scope.narrowedOwner == nil)
  }

  /// The key narrows the list to the active application and back, and a
  /// band names it only while narrowed.
  @Test
  func theKeyNarrowsAndRestores() {
    let (filter, surface) = makeFilter()
    filter.begin(fullWindows: rows, activeApplication: finder)
    #expect(filter.shownWindows.count == rows.count)
    filter.toggleScope()
    #expect(filter.shownWindows.map(\.ownerProcessIdentifier).allSatisfy { $0 == finder })
    #expect(surface.scopeBands.last == ScopeBand(appName: "Finder", toggleKey: nil))
    filter.toggleScope()
    #expect(filter.shownWindows.count == rows.count)
    #expect(surface.scopeBands.last == .some(nil))
  }

  /// Another application's window never matches while narrowed, and a
  /// parked window of the active application stays parked.
  @Test
  func narrowingHoldsForQueriesAndModes() {
    let (filter, _) = makeFilter()
    filter.scope.configured = .frontApp
    filter.begin(fullWindows: rows, filtering: true, activeApplication: finder)
    filter.append("o")
    #expect(filter.shownWindows.map(\.id) == [rows[0].id, rows[2].id, rows[3].id])
    #expect(filter.shownWindows.last?.isMinimized == true)
  }

  /// The query stays when the scope switches; the choice stays on its row
  /// when the row is still listed.
  @Test
  func switchingKeepsTheQueryAndAListedChoice() {
    let (filter, surface, selection) = makeFilterAndSelection()
    filter.begin(fullWindows: rows, filtering: true, activeApplication: finder)
    filter.append("o")
    selection.retarget(to: filter.shownWindows.map(\.id), selecting: rows[2].id)
    filter.toggleScope()
    #expect(surface.updatedQueries.last == "o")
    #expect(selection.chosenID == rows[2].id)
  }

  /// A choice the narrowed list leaves out moves to its first row.
  @Test
  func switchingAwayFromAChoiceTakesTheFirstRow() {
    let (filter, _, selection) = makeFilterAndSelection()
    filter.begin(fullWindows: rows, activeApplication: finder)
    selection.retarget(to: filter.shownWindows.map(\.id), selecting: rows[1].id)
    filter.toggleScope()
    #expect(selection.chosenID == filter.shownWindows.first?.id)
    #expect(filter.shownWindows.first?.ownerProcessIdentifier == finder)
  }

  /// This process in front narrows to its own rows.
  @Test
  func thisProcessInFrontKeepsItsOwnRows() {
    let own = ownedRow(90, owner: 900, app: "Lanterna", title: "Settings")
    let (filter, _) = makeFilter()
    filter.scope.configured = .frontApp
    filter.begin(fullWindows: rows + [own], activeApplication: 900)
    #expect(filter.shownWindows.map(\.id) == [own.id])
  }

  // MARK: Private

  private let finder: pid_t = 10

  private var rows: [WindowItem] {
    [
      ownedRow(1, owner: finder, app: "Finder", title: "Downloads"),
      ownedRow(2, owner: 20, app: "Safari", title: "Front page"),
      ownedRow(3, owner: finder, app: "Finder", title: "Documents"),
      ownedRow(4, owner: finder, app: "Finder", title: "Old folder", isMinimized: true),
    ]
  }

  private func makeFilter() -> (PanelFilter, FakeSurface) {
    let (filter, surface, _) = makeFilterAndSelection()
    return (filter, surface)
  }

  private func makeFilterAndSelection() -> (PanelFilter, FakeSurface, PanelSelection) {
    let surface = FakeSurface()
    surface.isPresented = true
    let selection = PanelSelection(surface: surface)
    let filter = PanelFilter(selection: selection, surface: surface)
    filter.writeLine = { _ in }
    return (filter, surface, selection)
  }

}
