@testable import Lanterna
import Testing

// MARK: - PanelPresenterScrollTests

/// What a scroll step does to a panel that is up.
///
/// The panel only calls while the scroll switch is on, gathering wheel
/// amounts into whole steps. What is settled here is the presenter's
/// half: that a step moves the single choice the keyboard moves without
/// wrapping at either end, and that with the switch off the choice stays
/// where the keyboard left it.
@MainActor
struct PanelPresenterScrollTests {

  @Test
  func aStepDownMovesTheChoiceOneRow() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.scrollSelect = true

    let opening = fixture.presenter.selection.chosenID
    #expect(opening == fixture.windows[1].id)
    fixture.surface.onScrollStep?(1)

    #expect(fixture.presenter.selection.chosenID == fixture.windows[2].id)
    #expect(fixture.surface.shownSelections == [fixture.windows[2].id])
  }

  @Test
  func stepsStopAtBothEnds() {
    let fixture = Fixture(entryCount: 3, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.scrollSelect = true

    for _ in 0 ..< 10 {
      fixture.surface.onScrollStep?(1)
    }
    #expect(fixture.presenter.selection.chosenID == fixture.windows.last?.id)
    for _ in 0 ..< 10 {
      fixture.surface.onScrollStep?(-1)
    }
    #expect(fixture.presenter.selection.chosenID == fixture.windows.first?.id)
  }

  @Test
  func aStepWithTheSwitchOffMovesNothing() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    let opening = fixture.presenter.selection.chosenID
    fixture.surface.onScrollStep?(1)

    #expect(fixture.presenter.selection.chosenID == opening)
    #expect(fixture.surface.shownSelections.isEmpty)
  }

}
