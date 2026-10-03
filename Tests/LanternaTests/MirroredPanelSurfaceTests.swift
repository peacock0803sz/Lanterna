import AppKit
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
    // Dismissing reaches the panel that was never shown as well; for
    // that panel the dismissal changes nothing.
    #expect(second.dismissCount == 1)
    #expect(surface.isPresented == false)
  }

  /// The primary panel would sit with the cursor if it resolved the
  /// every-display choice itself; held to its pool position, it sizes
  /// for and centres on the first display instead.
  @Test
  func everyDisplayHoldsEachPanelToItsPoolPosition() throws {
    let screen = try #require(NSScreen.screens.first)
    let panel = SwitcherPanel()
    panel.displayTarget = .all
    panel.displayResolver = resolver(cursor: CGPoint(x: 1600, y: 100))
    let surface = MirroredPanelSurface(panels: [panel], keyResolver: resolver(cursor: nil))
    surface.displayTarget = .all
    surface.present(windows: windows(), selecting: nil)
    #expect(panel.assignedScreenIndex == 0)
    #expect(panel.resolvedScreenIndex == 0)
    #expect(abs(panel.frame.midX - screen.visibleFrame.midX) < 1)
    surface.dismiss()
  }

  @Test
  func singleTargetLeavesThePrimaryPanelToResolveItself() {
    let panel = SwitcherPanel()
    panel.assignedScreenIndex = 0
    let surface = MirroredPanelSurface(panels: [panel], keyResolver: resolver(cursor: nil))
    surface.displayTarget = .primary
    surface.present(windows: windows(), selecting: nil)
    #expect(panel.assignedScreenIndex == nil)
    surface.dismiss()
  }

  @Test
  func placingOnADisplayRefitsAndCentresThePanel() throws {
    let screen = try #require(NSScreen.screens.first)
    let panel = SwitcherPanel()
    panel.present(windows: windows(), selecting: nil)
    panel.setFrameOrigin(NSPoint(x: panel.frame.minX + 300, y: panel.frame.minY + 100))
    panel.place(onScreen: 0)
    let expected = PanelMetrics.fittedWidth(
      PanelMetrics.width(for: panel.appearanceScale, step: panel.appearanceWidth),
      in: screen.visibleFrame.width
    )
    #expect(panel.contentRect(forFrameRect: panel.frame).width == expected)
    #expect(abs(panel.frame.midX - screen.visibleFrame.midX) < 1)
    #expect(abs(panel.frame.midY - screen.visibleFrame.midY) < 1)
    #expect(panel.assignedScreenIndex == 0)
    panel.dismiss()
  }

  @Test
  func aHeldPanelLeavesDisplayChangesToTheComposite() {
    let panel = SwitcherPanel()
    panel.present(windows: windows(), selecting: nil)
    panel.assignedScreenIndex = 0
    panel.setFrameOrigin(NSPoint(x: 17, y: 23))
    panel.screensChanged()
    #expect(panel.frame.origin == NSPoint(x: 17, y: 23))
    panel.dismiss()
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
      focusedFrame: { _ in nil },
      screens: { infos }
    )
  }

  private func windows() -> [WindowItem] {
    SampleWindows.make(count: 3)
  }

}
