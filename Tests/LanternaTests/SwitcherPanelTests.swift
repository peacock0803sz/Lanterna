import AppKit
@testable import Lanterna
import SwiftUI
import Testing

// MARK: - SwitcherPanelTests

/// `defer: true` means no window-server window is created, so an instance can
/// be inspected — and driven through `update(windows:)` — without a running
/// application.
@MainActor
struct SwitcherPanelTests {

  // MARK: Internal

  @Test
  func panelIsANonActivatingFloatingOverlay() {
    let panel = panel()
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.level == .floating)
    #expect(panel.canBecomeKey == true)
    #expect(panel.canBecomeMain == false)
    #expect(panel.hidesOnDeactivate == false)
  }

  /// Said because the opposite was once written down as the way to let a
  /// panel take keys without activating, and a sketch that says so is still
  /// there to be copied from. The flag decides only whether a click makes
  /// the panel key; it has no say over asking for key status outright. If
  /// it is ever set to true, this is what says so.
  @Test
  func thePanelDoesNotWaitToBeNeededBeforeItCanTakeKeys() {
    #expect(panel().becomesKeyOnlyIfNeeded == false)
  }

  @Test
  func panelJoinsEverySpaceAndStaysOutOfTheWindowCycle() {
    let panel = panel()
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(panel.collectionBehavior.contains(.ignoresCycle))
  }

  /// An empty list still takes the one line saying there is nothing.
  @Test(arguments: [0, 3, 30])
  func panelSizeFollowsTheContent(rowCount: Int) {
    let panel = panel(rowCount: rowCount)
    let contentRect = panel.contentRect(forFrameRect: panel.frame)
    #expect(contentRect.width == PanelMetrics.width)
    #expect(contentRect.height == PanelMetrics.height(rowCount: max(rowCount, 1)))
  }

  /// The height has to follow a swapped-in list as closely as it follows the
  /// one the panel was built with, because from the second appearance on it
  /// is the only thing setting the size.
  @Test(arguments: [0, 1, 3, 30])
  func updatedSizeFollowsTheNewContent(rowCount: Int) {
    let panel = panel(rowCount: 5)
    panel.update(windows: SampleWindows.make(count: rowCount))
    let contentRect = panel.contentRect(forFrameRect: panel.frame)
    #expect(contentRect.width == PanelMetrics.width)
    #expect(contentRect.height == PanelMetrics.height(rowCount: max(rowCount, 1)))
  }

  /// A list with parked rows draws one heading row for the subgroup, and the height
  /// makes room for it, so the last parked row stays clear of the panel edge.
  @Test
  func aParkedGroupMakesRoomForItsHeading() {
    let panel = panel(rowCount: 5)
    let windows = SampleWindows.make(count: 3)
    panel.update(windows: [windows[0], windows[1], windows[2].settingHidden(true)])
    let contentRect = panel.contentRect(forFrameRect: panel.frame)
    #expect(contentRect.height == PanelMetrics.height(rowCount: 4))
  }

  /// A list swapped in while the panel is up makes the same room for the heading,
  /// and a failure note grows the panel from that height.
  @Test
  func aSwappedInParkedGroupMakesRoomForItsHeading() {
    let panel = panel(rowCount: 5)
    let windows = SampleWindows.make(count: 3)
    panel.updateList(
      windows: [windows[0], windows[1], windows[2].settingHidden(true)],
      selecting: nil,
      query: "",
      filterActive: false
    )
    #expect(panel.contentRect(forFrameRect: panel.frame).height == PanelMetrics.height(rowCount: 4))
    panel.showNotice("Couldn't minimize")
    #expect(
      panel.contentRect(forFrameRect: panel.frame).height
        == PanelMetrics.height(rowCount: 4) + PanelMetrics.noticeHeight
    )
  }

  /// A row its mode keeps out takes no height: no row and no heading for
  /// it. A query that matches it brings its row and its heading back.
  @Test
  func aRowItsModeKeepsOutTakesNoHeight() {
    let panel = panel(rowCount: 5)
    panel.displayModes = DisplayModes(
      otherSpace: .show,
      hiddenApp: .separateAtBottom,
      minimized: .hide,
      fullscreen: .show
    )
    let windows = SampleWindows.make(count: 3)
    let rows = [windows[0], windows[1], windows[2].settingMinimized(true)]
    panel.updateList(windows: rows, selecting: nil, query: "", filterActive: false)
    #expect(panel.contentRect(forFrameRect: panel.frame).height == PanelMetrics.height(rowCount: 2))
    panel.update(windows: rows)
    #expect(panel.contentRect(forFrameRect: panel.frame).height == PanelMetrics.height(rowCount: 2))
    panel.updateList(windows: [rows[2]], selecting: nil, query: rows[2].appName, filterActive: true)
    #expect(
      panel.contentRect(forFrameRect: panel.frame).height
        == PanelMetrics.height(rowCount: 2)
        + PanelMetrics.filterChromeHeight(query: rows[2].appName, filterActive: true)
    )
  }

  /// A grouped list draws a heading over each group, and the height makes
  /// room for every heading as it does for every row.
  @Test
  func groupHeadingsTakeHeight() throws {
    let panel = panel(rowCount: 5)
    var grouping = GroupingPolicy()
    grouping.mode = .manual
    grouping.groupCount = 2
    let windows = SampleWindows.make(count: 3)
    let moved = try #require(windows[2].bundleIdentifier)
    #expect(windows[0].bundleIdentifier != moved)
    grouping.assignments = [GroupAssignment(bundleID: moved, group: 2)]
    panel.grouping = grouping
    panel.update(windows: windows)
    #expect(panel.contentRect(forFrameRect: panel.frame).height == PanelMetrics.height(rowCount: 5))
    panel.updateList(windows: windows, selecting: nil, query: "", filterActive: false)
    #expect(panel.contentRect(forFrameRect: panel.frame).height == PanelMetrics.height(rowCount: 5))
  }

  /// A query typed in one appearance is gone when the next one opens:
  /// the view draws every row it is handed, and the height counts them
  /// all. The chrome follows what the appearance says, not the last one.
  @Test
  func anAppearanceOpensOnAnEmptyQuery() {
    let panel = panel(rowCount: 5)
    let rows = SampleWindows.make(count: 3)
    panel.updateList(windows: [], selecting: nil, query: "x", filterActive: true)
    panel.present(windows: rows, selecting: rows[1].id)
    let view = (panel.contentView as? NSHostingView<SwitcherView>)?.rootView
    #expect(view?.query == "")
    #expect(view?.filterActive == false)
    #expect(
      panel.contentRect(forFrameRect: panel.frame).height
        == PanelMetrics.height(rowCount: PanelMetrics.drawnRowCount(rows, query: ""))
    )
  }

  /// Swapping the list must not cost a new hosting view: rebuilding the view
  /// tree on every appearance is exactly what keeping one panel avoids.
  @Test
  func updateKeepsTheHostingViewItAlreadyHas() {
    let panel = panel()
    let before = panel.contentView
    panel.update(windows: SampleWindows.make(count: 7))
    #expect(panel.contentView === before)
  }

  /// The row an appearance is given is the row it draws. Nothing else about
  /// the panel would say otherwise: `present` sizes itself from the list and
  /// puts the window up whether or not the choice ever reached the view, so
  /// an appearance that dropped it would leave a panel with every row
  /// looking unchosen and a caller certain one was highlighted.
  @Test
  func presentingDrawsTheRowItWasGiven() {
    let panel = panel()
    let windows = SampleWindows.make(count: 3)
    panel.present(windows: windows, selecting: windows[1].id)
    #expect(panel.shownSelection == windows[1].id)
    panel.dismiss()
  }

  /// A swapped-in list leaves the choice where it was. Assigning a new root
  /// view replaces every field of it, so the selection survives only by
  /// being carried across by hand — and this is the one case that says so:
  /// the row asked for here is neither the first of the new list nor
  /// nothing, so a swap that dropped the choice and one that recomputed it
  /// from the list both come out wrong.
  @Test
  func updatingKeepsTheRowThatWasAlreadyChosen() {
    let panel = panel()
    let windows = SampleWindows.make(count: 3)
    panel.present(windows: windows, selecting: windows[1].id)

    panel.update(windows: SampleWindows.make(count: 5))

    #expect(panel.shownSelection == windows[1].id)
    panel.dismiss()
  }

  /// A second appearance draws what it was given and not what the first one
  /// left behind. It needs its own case because the carrying-over above is
  /// exactly what puts it at risk: `present` swaps the list in first, which
  /// hands the old choice forward, and only writing the new one afterwards
  /// undoes that. Without the write the panel would go back up highlighting
  /// a row from the list that is gone, while whatever moves the selection
  /// believed it was back at the top.
  @Test
  func aSecondAppearanceDoesNotKeepTheLastOnesHighlight() {
    let panel = panel()
    let windows = SampleWindows.make(count: 4)
    panel.present(windows: windows, selecting: windows[2].id)
    panel.dismiss()

    panel.present(windows: windows, selecting: windows.first?.id)

    #expect(panel.shownSelection == windows.first?.id)
    panel.dismiss()
  }

  /// Nothing moves the panel between appearances, so a display change leaves
  /// a panel that is up wherever the old arrangement put it. Only the
  /// putting back is pinned here; what was seen when a panel was left where
  /// it fell is recorded on `screensChanged()`, and is not something a test
  /// can arrange.
  @Test
  func aPanelThatIsUpIsPutBackWhenTheScreensChange() {
    let panel = panel()
    panel.present(windows: SampleWindows.make(count: 3), selecting: nil)
    let belongs = panel.frame.origin
    panel.setFrameOrigin(NSPoint(x: belongs.x + 400, y: belongs.y + 200))

    panel.screensChanged()

    #expect(panel.frame.origin == belongs)
    panel.dismiss()
  }

  /// A panel that is not up is put in its place by the next appearance, and
  /// this runs whenever anyone plugs in a display.
  @Test
  func aPanelThatIsDownIsLeftAloneWhenTheScreensChange() {
    let panel = panel()
    panel.setFrameOrigin(NSPoint(x: 17, y: 23))
    panel.screensChanged()
    #expect(panel.frame.origin == NSPoint(x: 17, y: 23))
  }

  /// `aPanelThatIsUpIsPutBackWhenTheScreensChange` calls `screensChanged()`
  /// itself, which says only that the method does its job once something
  /// calls it. This says that something does. The subscription is made in
  /// `init` and nothing else in the app reaches it, so registering the wrong
  /// notification name or dropping the block would leave the method correct
  /// and never called, and a panel that is up when the displays are
  /// rearranged would stay wherever the old arrangement put it.
  ///
  /// The block is handed to `OperationQueue.main` rather than run on the
  /// thread that posts, so the assertion has to give the main queue its turn
  /// before reading the frame back. Yielding does that without waiting on a
  /// clock; the count is slack, not a measurement.
  @Test
  func aDisplayChangeNotificationPutsThePanelBack() async {
    let panel = panel()
    panel.present(windows: SampleWindows.make(count: 3), selecting: nil)
    let belongs = panel.frame.origin
    panel.setFrameOrigin(NSPoint(x: belongs.x + 400, y: belongs.y + 200))

    NotificationCenter.default.post(
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
    for _ in 0 ..< 10 {
      await Task.yield()
    }

    #expect(panel.frame.origin == belongs)
    panel.dismiss()
  }

  @Test
  func aWideStepSetsTheContentWidth() throws {
    let screen = try #require(NSScreen.screens.first)
    let panel = panel()
    panel.panelWidth = .widePlus
    panel.present(windows: SampleWindows.make(count: 3), selecting: nil)
    let expected = PanelMetrics.fittedWidth(
      PanelMetrics.width(for: .standard, step: .widePlus),
      in: screen.visibleFrame.width
    )
    #expect(panel.contentRect(forFrameRect: panel.frame).width == expected)
    panel.dismiss()
  }

  /// The width step is frozen at `present`, so changing it while the
  /// panel is up waits for the next appearance.
  @Test
  func aStepChangedWhileUpKeepsTheWidthThroughNarrowing() throws {
    let screen = try #require(NSScreen.screens.first)
    let panel = panel()
    panel.panelWidth = .widePlus
    let rows = SampleWindows.make(count: 3)
    panel.present(windows: rows, selecting: nil)
    panel.panelWidth = .narrowMinus
    panel.updateList(windows: [rows[0]], selecting: rows[0].id, query: "a", filterActive: true)
    let expected = PanelMetrics.fittedWidth(
      PanelMetrics.width(for: .standard, step: .widePlus),
      in: screen.visibleFrame.width
    )
    #expect(panel.contentRect(forFrameRect: panel.frame).width == expected)
    panel.dismiss()
  }

  // MARK: Private

  private func panel(rowCount: Int = 3) -> SwitcherPanel {
    SwitcherPanel(
      content: SwitcherView(
        windows: SampleWindows.make(count: rowCount),
        selectedID: nil,
        appearanceToken: 0,
        query: "",
        filterActive: false
      )
    )
  }

}

// MARK: - SwitcherPanelAppearanceModeTests

/// The light or dark look sits on the window, so a swapped-in list must
/// leave it as it was.
@MainActor
struct SwitcherPanelAppearanceModeTests {
  @Test
  func aFixedModeIsSetOnThePanelAndSurvivesASwap() {
    let panel = SwitcherPanel(appearanceMode: .dark)
    #expect(panel.appearance?.name == .darkAqua)
    panel.update(windows: SampleWindows.make(count: 3))
    #expect(panel.appearance?.name == .darkAqua)
  }

  @Test
  func theSystemModeLeavesThePanelFollowingTheSystem() {
    #expect(SwitcherPanel(appearanceMode: .system).appearance == nil)
  }
}
