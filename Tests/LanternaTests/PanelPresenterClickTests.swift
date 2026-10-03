@testable import Lanterna
import Testing

// MARK: - PanelPresenterClickTests

/// What a row click does to a panel that is up.
///
/// A click is the pointer's explicit choice: it picks the row and commits
/// to it whatever the switches say, through the same way out a commit key
/// takes. What is settled here is that the click takes the clicked row
/// down, writes the commit line naming the click, and leaves rows that
/// are gone — and non-rows, which never call — alone.
@MainActor
struct PanelPresenterClickTests {

  @Test
  func aClickTakesTheClickedRowDown() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    let target = fixture.windows[4]
    fixture.surface.onClickRow?(target.id)

    #expect(fixture.surface.dismissCount == 1)
    #expect(!fixture.surface.isPresented)
    #expect(fixture.switcher.targets.last?.id == target.id)
  }

  @Test
  func aClickWritesTheCommitLineNamingTheClick() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    let target = fixture.windows[4]
    fixture.surface.onClickRow?(target.id)

    let line = fixture.log.lines.first(where: { $0.hasPrefix("committed ") })
    #expect(line?.contains("after Click") == true)
    #expect(line?.contains(target.id.logWord) == true)
  }

  @Test
  func aClickCommitsWithTheSwitchesOff() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(fixture.presenter.hoverSelect == false)
    #expect(fixture.presenter.scrollSelect == false)

    fixture.surface.onClickRow?(fixture.windows[4].id)

    #expect(fixture.surface.dismissCount == 1)
    #expect(fixture.switcher.targets.last?.id == fixture.windows[4].id)
  }

}
