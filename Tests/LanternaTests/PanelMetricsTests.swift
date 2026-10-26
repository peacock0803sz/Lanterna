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

  /// Ten rows of 36 and the padding either side: the Cmd+Tab list at the
  /// standard text size and the standard limit.
  @Test
  func heightStopsAtTheRowLimit() {
    #expect(PanelMetrics.height(rowCount: 9) == 336)
    #expect(PanelMetrics.height(rowCount: 10) == 372)
    #expect(PanelMetrics.height(rowCount: 11) == 372)
    #expect(PanelMetrics.height(rowCount: 30) == 372)
  }

  @Test
  func heightFollowsTheChosenLimit() throws {
    let five = try #require(PanelRows(count: 5))
    let thirty = try #require(PanelRows(count: 30))
    #expect(PanelMetrics.height(rowCount: 40, for: .standard, rows: five) == 192)
    #expect(PanelMetrics.height(rowCount: 3, for: .standard, rows: five) == 120)
    #expect(PanelMetrics.height(rowCount: 40, for: .standard, rows: thirty) == 1092)
    #expect(PanelMetrics.height(rowCount: 20, for: .standard, rows: thirty) == 732)
  }

  /// The filter panel is the same list under the filter chrome: ten rows
  /// plus 43, and it shrinks with the rows when fewer are drawn.
  @Test
  func filterPanelAddsItsChromeToTheLimit() {
    func total(_ rowCount: Int, filterActive: Bool) -> CGFloat {
      PanelMetrics.totalHeight(
        rowCount: rowCount,
        query: "",
        filterActive: filterActive,
        notice: false,
        for: .standard
      )
    }
    #expect(total(30, filterActive: true) == 415)
    #expect(total(10, filterActive: true) == 415)
    #expect(total(4, filterActive: true) == 199)
    #expect(total(30, filterActive: false) == 372)
    #expect(total(4, filterActive: false) == 156)
  }

  /// The note and the band add to the rows shown, not to the limit's
  /// count of rows.
  @Test
  func noticeAndBandAddOverTheRowsShown() {
    #expect(
      PanelMetrics.totalHeight(
        rowCount: 30,
        query: "x",
        filterActive: true,
        notice: true,
        for: .standard
      ) == 437
    )
    #expect(
      PanelMetrics.totalHeight(
        rowCount: 30,
        query: "",
        filterActive: false,
        notice: false,
        scopeBand: true,
        for: .standard
      ) == 404
    )
  }

  /// At the largest text step each row is 45 and the chrome 54, so the
  /// same ten rows stand taller and the display fit is what stops them.
  @Test
  func largestTextStepScalesTheRowsAndTheChrome() {
    func total(visibleHeight: CGFloat) -> CGFloat {
      PanelMetrics.totalHeight(
        rowCount: 30,
        query: "",
        filterActive: true,
        notice: false,
        for: .large,
        visibleHeight: visibleHeight
      )
    }
    #expect(PanelMetrics.height(rowCount: 30, for: .large) == 462)
    #expect(total(visibleHeight: .infinity) == 516)
    #expect(total(visibleHeight: 1000) == 516)
    #expect(total(visibleHeight: 500) == 460)
  }

  /// The display's visible height, less the margin, caps the total
  /// whatever the limit asks for.
  @Test
  func displayHeightCapsTheTotal() throws {
    let thirty = try #require(PanelRows(count: 30))
    func total(visibleHeight: CGFloat) -> CGFloat {
      PanelMetrics.totalHeight(
        rowCount: 30,
        query: "",
        filterActive: true,
        notice: false,
        for: .standard,
        rows: thirty,
        visibleHeight: visibleHeight
      )
    }
    #expect(total(visibleHeight: 1400) == 1135)
    #expect(total(visibleHeight: 900) == 860)
    #expect(total(visibleHeight: 30) == 0)
    let size = PanelMetrics.panelSize(
      rowCount: 30,
      query: "",
      filterActive: false,
      notice: false,
      for: .standard,
      visibleHeight: 300
    )
    #expect(size.height == 260)
    #expect(size.width == 720)
  }

  @Test
  func fittingHeightKeepsTheMargin() {
    #expect(PanelMetrics.fittedHeight(372, in: 1000) == 372)
    #expect(PanelMetrics.fittedHeight(1092, in: 900) == 860)
    #expect(PanelMetrics.fittedHeight(372, in: 30) == 0)
    #expect(PanelMetrics.fittedHeight(372, in: .infinity) == 372)
    #expect(PanelMetrics.availableHeight(in: 900) == 860)
  }

  /// The note grows the frame by its own height, less what the display
  /// has no room for.
  @Test
  func noticeGrowthStopsAtTheDisplay() {
    #expect(PanelMetrics.noticeGrowth(from: 372, in: 1000, for: .standard) == 22)
    #expect(PanelMetrics.noticeGrowth(from: 372, in: .infinity, for: .standard) == 22)
    #expect(PanelMetrics.noticeGrowth(from: 350, in: 400, for: .standard) == 10)
    #expect(PanelMetrics.noticeGrowth(from: 360, in: 400, for: .standard) == 0)
    #expect(PanelMetrics.noticeGrowth(from: 372, in: 400, for: .standard) == 0)
    #expect(PanelMetrics.noticeGrowth(from: 372, in: 1000, for: .large) == 28)
  }

  /// A frame grown downward from a kept top edge is lifted back inside
  /// the display, and one already inside is left where it is.
  @Test
  func growingFrameStaysOnTheDisplay() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 900)
    let inside = CGRect(x: 396, y: 300, width: 720, height: 300)
    #expect(PanelMetrics.keptOnScreen(inside, in: visible) == inside)
    let below = CGRect(x: 396, y: -400, width: 720, height: 860)
    #expect(PanelMetrics.keptOnScreen(below, in: visible).minY == 20)
    let above = CGRect(x: 396, y: 700, width: 720, height: 300)
    #expect(PanelMetrics.keptOnScreen(above, in: visible).maxY == 880)
    let tooTall = CGRect(x: 396, y: -100, width: 720, height: 1000)
    #expect(PanelMetrics.keptOnScreen(tooTall, in: visible).maxY == 880)
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

  @Test
  func standardWidthStepKeepsTheCurrentWidth() {
    for level in TextScaleLevel.allCases {
      #expect(
        PanelMetrics.width(for: level, step: .standard) == PanelMetrics.width(for: level),
        "for \(level)"
      )
    }
  }

  @Test
  func widthEndsChangeOnlyTheWidth() {
    for level in TextScaleLevel.allCases {
      let narrow = PanelMetrics.width(for: level, step: .narrowMinus)
      let wide = PanelMetrics.width(for: level, step: .widePlus)
      let standard = PanelMetrics.width(for: level, step: .standard)
      #expect(narrow < standard, "for \(level)")
      #expect(wide > standard, "for \(level)")
      #expect(
        PanelMetrics.panelSize(
          rowCount: 5,
          query: "",
          filterActive: false,
          notice: false,
          for: level,
          step: .widePlus
        ).height
          == PanelMetrics.panelSize(
            rowCount: 5,
            query: "",
            filterActive: false,
            notice: false,
            for: level,
            step: .standard
          ).height,
        "for \(level)"
      )
    }
  }

  @Test
  func fittingWidthKeepsTheMargin() {
    #expect(PanelMetrics.screenMargin == 40)
    #expect(PanelMetrics.fittedWidth(720, in: 1512) == 720)
    #expect(PanelMetrics.fittedWidth(936, in: 900) == 860)
    #expect(PanelMetrics.fittedWidth(720, in: 30) == 0)
  }

  /// The padding stays put while the rows grow with the step.
  @Test
  func paddingStaysFixedAcrossSteps() {
    #expect(PanelMetrics.verticalPadding == 6)
    #expect(PanelMetrics.height(rowCount: 0, for: .large) == 12)
    #expect(PanelMetrics.height(rowCount: 30, for: .large) == 462)
  }
}
