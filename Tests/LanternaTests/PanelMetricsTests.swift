import Foundation
@testable import Lanterna
import Testing

// MARK: - PanelMetricsTests

struct PanelMetricsTests {
  @Test
  func heightGrowsWithRowCount() {
    // One literal pin on the contract, so changing a constant fails here
    // and not only inside the formula the other cases share.
    #expect(PanelMetrics.height(rowCount: 3) == 120)

    for rowCount in [0, 1, 3, 10] {
      let expected = CGFloat(rowCount) * PanelMetrics.rowHeight
        + 2 * PanelMetrics.verticalPadding
      #expect(PanelMetrics.height(rowCount: rowCount) == expected)
    }
  }

  /// A parked row under ordinary rows adds its heading and nothing more:
  /// no extra row stands between the ordinary rows and the subgroup.
  @Test @MainActor
  func aHeadingCountsAsARowWhenAnyRowIsParked() {
    let windows = SampleWindows.make(count: 3)
    #expect(PanelMetrics.drawnRowCount([]) == 1)
    #expect(PanelMetrics.drawnRowCount(windows) == 3)
    #expect(PanelMetrics.drawnRowCount([windows[0], windows[1].settingMinimized(true)]) == 3)
    #expect(PanelMetrics.drawnRowCount(windows.map { $0.settingHidden(true) }) == 4)
  }

  /// Each non-empty subgroup carries one heading row.
  @Test @MainActor
  func subgroupsAndHeadingsCountAsRows() {
    let windows = SampleWindows.make(count: 3)
    let allShow = DisplayModes(
      otherSpace: .show,
      hiddenApp: .show,
      minimized: .show,
      fullscreen: .show
    )
    #expect(PanelMetrics.drawnRowCount(windows, modes: allShow) == 3)
    let lone = [windows[0].settingMinimized(true)]
    #expect(PanelMetrics.drawnRowCount(lone, modes: .defaults) == 2)
    let mixed = [windows[0], windows[1].settingMinimized(true)]
    #expect(PanelMetrics.drawnRowCount(mixed, modes: .defaults) == 3)
    let twoGroups = [
      windows[0].settingMinimized(true),
      windows[1].settingHidden(true),
    ]
    #expect(PanelMetrics.drawnRowCount(twoGroups, modes: .defaults) == 4)
  }

  @Test
  func widthIsFixedByTheUIContract() {
    #expect(PanelMetrics.width == 720)
  }

  @Test
  func heightStopsAtTheCap() {
    #expect(PanelMetrics.maximumHeight == 400)
    #expect(PanelMetrics.height(rowCount: 11) == PanelMetrics.maximumHeight)
    #expect(PanelMetrics.height(rowCount: 30) == PanelMetrics.maximumHeight)
  }
}

extension PanelMetricsTests {
  @Test
  func scaledRowHeightsRoundToWholePoints() {
    let expected: [TextScaleLevel: CGFloat] = [
      .small: 31,
      .smallMedium: 33,
      .standard: 36,
      .largeMedium: 40,
      .large: 45,
    ]
    for level in TextScaleLevel.allCases {
      #expect(PanelMetrics.rowHeight(for: level) == expected[level], "for \(level)")
    }
    #expect(PanelMetrics.rowHeight(for: .standard) == PanelMetrics.rowHeight)
  }

  @Test
  func scaledWidthsRoundToWholePoints() {
    let expected: [TextScaleLevel: CGFloat] = [
      .small: 612,
      .smallMedium: 670,
      .standard: 720,
      .largeMedium: 806,
      .large: 900,
    ]
    for level in TextScaleLevel.allCases {
      #expect(PanelMetrics.width(for: level) == expected[level], "for \(level)")
    }
    #expect(PanelMetrics.width(for: .standard) == PanelMetrics.width)
  }

  @Test
  func scaledHeightKeepsTheCapOverTheTotal() {
    let chrome = PanelMetrics.filterChromeHeight(query: "x", filterActive: true, for: .large)
    let total = PanelMetrics.height(rowCount: 30, for: .large) + chrome
      + PanelMetrics.noticeHeight(for: .large)
    let largeTotal = PanelMetrics.totalHeight(
      rowCount: 30,
      query: "x",
      filterActive: true,
      notice: true,
      for: .large
    )
    #expect(largeTotal == PanelMetrics.maximumHeight)
    #expect(total > PanelMetrics.maximumHeight)
  }

  /// Fixed points, not the formula, so a constant change fails here.
  @Test
  func scaledChromeAndNoticeMatchFixedPoints() {
    let chrome: [TextScaleLevel: CGFloat] = [
      .small: 37,
      .smallMedium: 40,
      .standard: 43,
      .largeMedium: 48,
      .large: 54,
    ]
    let notice: [TextScaleLevel: CGFloat] = [
      .small: 19,
      .smallMedium: 20,
      .standard: 22,
      .largeMedium: 25,
      .large: 28,
    ]
    for level in TextScaleLevel.allCases {
      #expect(
        PanelMetrics.filterChromeHeight(query: "", filterActive: true, for: level)
          == chrome[level],
        "chrome for \(level)"
      )
      #expect(
        PanelMetrics.filterChromeHeight(query: "x", filterActive: true, for: level)
          == chrome[level],
        "query for \(level)"
      )
      #expect(PanelMetrics.noticeHeight(for: level) == notice[level], "notice for \(level)")
    }
  }

  @Test
  func standardChromeAndNoticeMatchUnscaled() {
    #expect(
      PanelMetrics.filterChromeHeight(query: "", filterActive: true, for: .standard)
        == PanelMetrics.filterChromeHeight(query: "", filterActive: true)
    )
    #expect(
      PanelMetrics.filterChromeHeight(query: "x", filterActive: true, for: .standard)
        == PanelMetrics.filterChromeHeight(query: "x", filterActive: true)
    )
    #expect(PanelMetrics.noticeHeight(for: .standard) == PanelMetrics.noticeHeight)
  }

  @Test
  func disabledFilterTakesNoHeight() {
    for level in TextScaleLevel.allCases {
      #expect(
        PanelMetrics.filterChromeHeight(query: "", filterActive: false, for: level) == 0,
        "empty for \(level)"
      )
      #expect(
        PanelMetrics.filterChromeHeight(query: "x", filterActive: false, for: level) == 0,
        "query for \(level)"
      )
    }
    #expect(PanelMetrics.filterChromeHeight(query: "x", filterActive: false) == 0)
  }

  /// The padding and the cap stay put while the rows grow, so a large
  /// step scrolls sooner rather than outgrowing the screen.
  @Test
  func paddingAndCapStayFixedAcrossSteps() {
    #expect(PanelMetrics.verticalPadding == 6)
    #expect(PanelMetrics.maximumHeight == 400)
    #expect(PanelMetrics.height(rowCount: 0, for: .large) == 12)
    #expect(PanelMetrics.height(rowCount: 30, for: .large) == PanelMetrics.maximumHeight)
  }
}
