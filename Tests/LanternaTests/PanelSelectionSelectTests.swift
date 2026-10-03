@testable import Lanterna
import Testing

// MARK: - PanelSelectionSelectTests

/// Putting the choice on a named row, seen from outside.
///
/// What the arithmetic does with a list of identities is settled in
/// `SelectionCursorTests`. What is settled here is the one thing only
/// this entry does: that naming a row moves the choice there and tells
/// the panel through the redraw entry, and that naming a row that is
/// gone leaves the choice — and the panel — where they were.
@MainActor
struct PanelSelectionSelectTests {

  // MARK: Internal

  @Test
  func namingARowMovesTheChoiceThere() {
    let surface = FakeSurface()
    let selection = PanelSelection(surface: surface)
    selection.beginSecond(rows.map(\.id))
    selection.select(rows[2].id)
    #expect(selection.chosenID == rows[2].id)
    #expect(surface.shownSelections.last == rows[2].id)
    #expect(surface.shownSelections.count == 1)
  }

  @Test
  func namingAGoneRowLeavesTheChoiceWhereItWas() {
    let surface = FakeSurface()
    let selection = PanelSelection(surface: surface)
    selection.beginSecond(rows.map(\.id))
    selection.select(rows[1].id)
    selection.retarget(to: [rows[0].id, rows[2].id], selecting: rows[2].id)
    selection.select(rows[1].id)
    #expect(selection.chosenID == rows[2].id)
    #expect(surface.shownSelections.last == rows[2].id)
  }

  // MARK: Private

  private var rows: [WindowItem] {
    SampleWindows.make(count: 3)
  }

}
