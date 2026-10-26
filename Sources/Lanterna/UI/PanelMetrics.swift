import Foundation

/// Geometry of the switcher panel.
enum PanelMetrics {
  static let width: CGFloat = 720
  static let rowHeight: CGFloat = 36
  static let verticalPadding: CGFloat = 6

  /// Extra height for the failure note. An estimate, for the reason the
  /// filter chrome's is.
  static let noticeHeight: CGFloat = 22

  /// Extra height for the band over a list narrowed to one application.
  static let scopeBandHeight: CGFloat = 32

  /// The total margin kept clear on the sides and above and below, so
  /// a wide or tall panel on a small display stays on screen. Mirrors
  /// the log window's margin.
  static let screenMargin: CGFloat = 40

  /// Extra height for the filter chrome while filtering is on, whether the query
  /// reads anything or not. An estimate, because SwiftUI lays the query row
  /// out.
  static func filterChromeHeight(query _: String, filterActive: Bool) -> CGFloat {
    guard filterActive else { return 0 }
    return 43
  }

  /// How many rows the list draws for these windows under this query:
  /// one for each window row, and one heading row for each non-empty
  /// subgroup. Split the way the view splits them, so a row the modes keep
  /// out takes no height. The list gives every row at least `rowHeight`.
  static func drawnRowCount(
    _ windows: [WindowItem],
    modes: DisplayModes = .defaults,
    query: String = "",
    exclusions: [ExclusionRule] = [],
    fuzzy: Bool = false,
    ordering: SearchOrdering = .mru,
    grouping: GroupingPolicy = GroupingPolicy()
  ) -> Int {
    PanelLayout.make(
      rows: windows,
      modes: modes,
      query: query,
      exclusions: exclusions,
      fuzzy: fuzzy,
      ordering: ordering,
      grouping: grouping
    ).drawnRowCount
  }

  /// Height for a given number of rows at the standard row limit. The
  /// panel grows with its content until the limit, past which the list
  /// scrolls instead of the panel growing.
  static func height(rowCount: Int) -> CGFloat {
    height(rowCount: rowCount, for: .standard)
  }

  /// The row height one step draws, in whole points.
  static func rowHeight(for scale: TextScaleLevel) -> CGFloat {
    scale.scaledRowHeight
  }

  /// The panel width a text step draws at a width step, in whole
  /// points. The standard width step draws the text-scaled width
  /// unchanged.
  static func width(for scale: TextScaleLevel, step: PanelWidth) -> CGFloat {
    step.applied(to: scale.scaledWidth)
  }

  /// The panel width one step draws, in whole points.
  static func width(for scale: TextScaleLevel) -> CGFloat {
    width(for: scale, step: .standard)
  }

  /// Fits a content width into a visible width, keeping the margin.
  /// A fitting width passes through; only an overflow is cut.
  /// Never drops below zero, so a display narrower than the margin
  /// yields zero rather than a negative width.
  static func fittedWidth(_ width: CGFloat, in visibleWidth: CGFloat) -> CGFloat {
    min(width, max(visibleWidth - screenMargin, 0))
  }

  /// Fits a content height into a visible height, keeping the margin.
  /// A fitting height passes through; only an overflow is cut. Never
  /// drops below zero, like `fittedWidth`.
  static func fittedHeight(_ height: CGFloat, in visibleHeight: CGFloat) -> CGFloat {
    min(height, availableHeight(in: visibleHeight))
  }

  /// The most height a panel may take on a display with this visible
  /// height. An unresolved display passes `.infinity` and so limits
  /// nothing.
  static func availableHeight(in visibleHeight: CGFloat) -> CGFloat {
    max(visibleHeight - screenMargin, 0)
  }

  /// Height for a given number of rows at one step. The rows shown stop
  /// at the row limit while the rows drawn grow, so the panel stops
  /// growing and the list scrolls instead.
  static func height(
    rowCount: Int,
    for scale: TextScaleLevel,
    rows: PanelRows = .standard
  ) -> CGFloat {
    precondition(rowCount >= 0, "rowCount must not be negative")
    return CGFloat(min(rowCount, rows.count)) * rowHeight(for: scale) + verticalPadding * 2
  }

  /// Extra height for the filter chrome at one step, scaled the way
  /// the query text scales. An estimate, for the reason the unscaled
  /// one is.
  static func filterChromeHeight(query: String, filterActive: Bool, for scale: TextScaleLevel) -> CGFloat {
    (filterChromeHeight(query: query, filterActive: filterActive) * scale.factor).rounded()
  }

  /// Extra height for the failure note at one step, scaled the way
  /// the note text scales. An estimate, for the reason the unscaled
  /// filter chrome's is.
  static func noticeHeight(for scale: TextScaleLevel) -> CGFloat {
    (noticeHeight * scale.factor).rounded()
  }

  /// Extra height for the band over a list narrowed to one application,
  /// at one step. An estimate, for the reason the filter chrome's is.
  static func scopeBandHeight(for scale: TextScaleLevel) -> CGFloat {
    (scopeBandHeight * scale.factor).rounded()
  }

  /// How far the frame may grow for the failure note: the note's own
  /// height, less whatever the display has no room for.
  static func noticeGrowth(
    from height: CGFloat,
    in visibleHeight: CGFloat,
    for scale: TextScaleLevel
  ) -> CGFloat {
    min(noticeHeight(for: scale), max(availableHeight(in: visibleHeight) - height, 0))
  }

  /// Moves a frame up or down just enough to sit inside a visible area,
  /// half the margin clear of each edge. A frame already inside stays
  /// where it is; one taller than the room keeps its top on screen.
  static func keptOnScreen(_ frame: CGRect, in visible: CGRect) -> CGRect {
    let inset = screenMargin / 2
    var frame = frame
    frame.origin.y = max(frame.origin.y, visible.minY + inset)
    frame.origin.y = min(frame.origin.y, visible.maxY - inset - frame.height)
    return frame
  }

  /// The full content height at one step: the rows shown plus chrome
  /// plus the band and the note when they show, fitted to the display
  /// as one total so a large step or a long limit never outgrows it.
  static func totalHeight(
    rowCount: Int,
    query: String,
    filterActive: Bool,
    notice: Bool,
    scopeBand: Bool = false,
    for scale: TextScaleLevel,
    rows: PanelRows = .standard,
    visibleHeight: CGFloat = .infinity
  ) -> CGFloat {
    var total = height(rowCount: rowCount, for: scale, rows: rows)
      + filterChromeHeight(query: query, filterActive: filterActive, for: scale)
    if notice {
      total += noticeHeight(for: scale)
    }
    if scopeBand {
      total += scopeBandHeight(for: scale)
    }
    return fittedHeight(total, in: visibleHeight)
  }

  /// The content size for a row count at one step, so the panel and
  /// its tests take all three numbers from one place.
  static func panelSize(
    rowCount: Int,
    query: String,
    filterActive: Bool,
    notice: Bool,
    scopeBand: Bool = false,
    for scale: TextScaleLevel,
    step: PanelWidth = .standard,
    rows: PanelRows = .standard,
    visibleHeight: CGFloat = .infinity
  ) -> CGSize {
    CGSize(
      width: width(for: scale, step: step),
      height: totalHeight(
        rowCount: rowCount,
        query: query,
        filterActive: filterActive,
        notice: notice,
        scopeBand: scopeBand,
        for: scale,
        rows: rows,
        visibleHeight: visibleHeight
      )
    )
  }
}
