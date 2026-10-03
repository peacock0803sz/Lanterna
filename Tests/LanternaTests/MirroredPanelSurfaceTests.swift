import CoreGraphics
import Foundation
@testable import Lanterna
import Testing

@MainActor
struct MirroredPanelSurfaceTests {

  // MARK: Internal

  @Test
  func presentFansOutTheSameContent() {
    let first = FakeSurface()
    let second = FakeSurface()
    let surface = MirroredPanelSurface(
      panels: [first, second],
      keyResolver: resolver(cursor: CGPoint(x: 100, y: 100))
    )
    surface.displayTarget = .all
    let rows = windows()
    surface.present(windows: rows, selecting: rows[1].id, filterActive: true)
    for fake in [first, second] {
      #expect(fake.presentedLists.last?.map(\.id) == rows.map(\.id))
      #expect(fake.presentedSelections.last == rows[1].id)
      #expect(fake.presentedActives.last == true)
    }
  }

  @Test
  func keysGoToTheCursorDisplayPanelOnly() {
    let first = FakeSurface()
    let second = FakeSurface()
    let surface = MirroredPanelSurface(
      panels: [first, second],
      keyResolver: resolver(cursor: CGPoint(x: 1600, y: 100))
    )
    surface.displayTarget = .all
    surface.present(windows: windows(), selecting: nil)
    #expect(surface.takeKeys() == true)
    #expect(first.takeKeysCount == 0)
    #expect(second.takeKeysCount == 1)
  }

  @Test
  func selectionAndNarrowingFanOut() {
    let first = FakeSurface()
    let second = FakeSurface()
    let surface = MirroredPanelSurface(
      panels: [first, second],
      keyResolver: resolver(cursor: nil)
    )
    surface.displayTarget = .all
    let rows = windows()
    surface.present(windows: rows, selecting: nil)
    surface.showSelection(rows[2].id)
    surface.updateList(windows: [rows[0]], selecting: rows[0].id, query: "a", filterActive: true)
    for fake in [first, second] {
      #expect(fake.shownSelections.last == rows[2].id)
      #expect(fake.updatedLists.last?.map(\.id) == [rows[0].id])
      #expect(fake.updatedQueries.last == "a")
    }
  }

  @Test
  func dismissTakesDownEveryPanel() {
    let first = FakeSurface()
    let second = FakeSurface()
    let surface = MirroredPanelSurface(
      panels: [first, second],
      keyResolver: resolver(cursor: nil)
    )
    surface.displayTarget = .all
    surface.present(windows: windows(), selecting: nil)
    #expect(surface.isPresented == true)
    surface.dismiss()
    #expect(first.dismissCount == 1)
    #expect(second.dismissCount == 1)
    #expect(surface.isPresented == false)
  }

  @Test
  func singlePanelBehavesSingly() {
    let only = FakeSurface()
    let surface = MirroredPanelSurface(
      panels: [only],
      keyResolver: resolver(cursor: nil)
    )
    let rows = windows()
    surface.present(windows: rows, selecting: rows[0].id)
    #expect(only.presentedLists.last?.count == 3)
    #expect(surface.takeKeys() == true)
    #expect(only.takeKeysCount == 1)
    surface.dismiss()
    #expect(only.dismissCount == 1)
  }

  @Test
  func singleTargetShowsOnlyFirstPanel() {
    let first = FakeSurface()
    let second = FakeSurface()
    let surface = MirroredPanelSurface(
      panels: [first, second],
      keyResolver: resolver(cursor: CGPoint(x: 1600, y: 100))
    )
    surface.displayTarget = .primary
    let rows = windows()
    surface.present(windows: rows, selecting: rows[1].id, filterActive: true)
    #expect(first.presentedLists.last?.map(\.id) == rows.map(\.id))
    #expect(first.presentedSelections.last == rows[1].id)
    #expect(second.presentedLists.isEmpty)
    #expect(surface.isPresented == true)
    #expect(surface.takeKeys() == true)
    #expect(first.takeKeysCount == 1)
    #expect(second.takeKeysCount == 0)
    surface.showSelection(rows[2].id)
    #expect(first.shownSelections.last == rows[2].id)
    #expect(second.shownSelections.isEmpty)
    surface.dismiss()
    #expect(first.dismissCount == 1)
    // Taking everything down reaches the never-shown panel too, which
    // answers a dismissal it never opened with silence.
    #expect(second.dismissCount == 1)
    #expect(surface.isPresented == false)
  }

  // MARK: Private

  private var screens: [DisplayInfo] {
    [
      DisplayInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 944), isPrimary: true),
      DisplayInfo(frame: CGRect(x: 1512, y: 0, width: 1080, height: 720), isPrimary: false),
    ]
  }

  private func resolver(cursor: CGPoint?) -> DisplayResolver {
    let infos = screens
    return DisplayResolver(
      cursor: { cursor },
      frontmostPID: { nil },
      focusedPosition: { _ in nil },
      screens: { infos }
    )
  }

  private func windows() -> [WindowItem] {
    SampleWindows.make(count: 3)
  }

}
