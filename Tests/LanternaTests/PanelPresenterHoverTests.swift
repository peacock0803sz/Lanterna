@testable import Lanterna
import Testing

// MARK: - PanelPresenterHoverTests

/// What a row hover does to a panel that is up.
///
/// The view only calls while the hover switch is on, and only for window
/// rows. What is settled here is the presenter's half: that a hover moves
/// the single choice the keyboard moves, through the same entry, and that
/// with the switch off the choice stays where the keyboard left it.
@MainActor
struct PanelPresenterHoverTests {

  @Test
  func aHoverMovesTheChoiceThroughTheRedrawEntry() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.hoverSelect = true

    let target = fixture.windows[4].id
    fixture.surface.onHoverRow?(target)

    #expect(fixture.presenter.selection.chosenID == target)
    #expect(fixture.surface.shownSelections.last == target)
    #expect(fixture.surface.presentedLists.count == 1)
  }

  @Test
  func aHoverWithTheSwitchOffMovesNothing() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    let opening = fixture.presenter.selection.chosenID
    fixture.surface.onHoverRow?(fixture.windows[4].id)

    #expect(fixture.presenter.selection.chosenID == opening)
    #expect(fixture.surface.shownSelections.isEmpty)
  }

  @Test
  func aHoverKeepsAnsweringToTheKeyboardAfterwards() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.hoverSelect = true

    fixture.surface.onHoverRow?(fixture.windows[4].id)
    fixture.presenter.selection.moveToNext()

    #expect(fixture.presenter.selection.chosenID == fixture.windows[5].id)
  }

}
