import AppKit
@testable import Lanterna
import Testing

// MARK: - FastSearchSelectionTests

/// Which row a filter that commits on release chooses: the best match
/// other than the window already in front, settled again on every change
/// of the query.
@MainActor
struct FastSearchSelectionTests {

  // MARK: Internal

  @Test
  func theFrontWindowIsSteppedPastWhenItMatchesFirst() {
    let made = makeFilter(origin: .fastSearch)
    made.filter.append("sa")
    #expect(made.selection.chosenID == safariOther)
  }

  @Test
  func theFrontWindowIsChosenWhenItIsTheOnlyMatch() {
    let made = makeFilter(origin: .fastSearch)
    made.filter.append("update")
    #expect(made.selection.chosenID == front)
  }

  @Test
  func typingAfterMovingChoosesTheBestMatchAgain() {
    let made = makeFilter(origin: .typed)
    made.filter.append("s")
    made.selection.moveToNext()
    #expect(made.selection.chosenID != safariOther)
    made.filter.append("a")
    #expect(made.selection.chosenID == safariOther)
  }

  @Test
  func shorteningChoosesTheBestMatchForTheShorterQuery() {
    let made = makeFilter(origin: .fastSearch)
    made.filter.append("app")
    #expect(made.selection.chosenID == finder)
    made.filter.removeLast()
    made.filter.removeLast()
    #expect(made.selection.chosenID == safariOther)
  }

  @Test
  func clearingChoosesTheSecondInUseOrder() {
    let made = makeFilter(origin: .fastSearch)
    made.filter.append("app")
    #expect(made.filter.clear())
    #expect(made.selection.chosenID == safariOther)
  }

  @Test
  func aSwappedListKeepsTheChosenRow() {
    let made = makeFilter(origin: .fastSearch)
    made.filter.append("a")
    made.selection.moveToNext()
    let chosen = made.selection.chosenID
    made.filter.replace(fullWindows: rows)
    #expect(made.selection.chosenID == chosen)
  }

  @Test
  func anInvokedFilterKeepsItsOwnRule() {
    let made = makeFilter(origin: .invoked)
    made.filter.append("update")
    #expect(made.selection.chosenID == front)
    made.filter.removeLast()
    made.filter.append("e")
    #expect(made.selection.chosenID == front)
  }

  // MARK: Private

  private struct Harness {
    let filter: PanelFilter
    let selection: PanelSelection
  }

  private let front = WindowItem.Identifier(windowID: 1)
  private let safariOther = WindowItem.Identifier(windowID: 2)
  private let finder = WindowItem.Identifier(windowID: 3)

  private var rows: [WindowItem] {
    [
      row(appName: "Safari", title: "Update available", id: 1),
      row(appName: "Safari", title: "Downloads", id: 2),
      row(appName: "Finder", title: "Applications", id: 3),
    ]
  }

  private func row(appName: String, title: String, id: CGWindowID) -> WindowItem {
    WindowItem(
      id: WindowItem.Identifier(windowID: id),
      ownerProcessIdentifier: 0,
      appName: appName,
      bundleIdentifier: nil,
      windowTitle: title,
      kind: .standard,
      isMinimized: false,
      icon: NSImage(size: NSSize(width: 1, height: 1))
    )
  }

  private func makeFilter(origin: FilterOrigin) -> Harness {
    let surface = FakeSurface()
    surface.isPresented = true
    let selection = PanelSelection(surface: surface)
    let filter = PanelFilter(selection: selection, surface: surface)
    filter.autoFocusSingleCandidate = false
    selection.beginSecond(rows.map(\.id))
    filter.begin(fullWindows: rows, filtering: true, origin: origin)
    return Harness(filter: filter, selection: selection)
  }

}
