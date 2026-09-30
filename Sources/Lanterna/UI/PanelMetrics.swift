import Foundation

/// Geometry of the switcher panel.
enum PanelMetrics {
  static let width: CGFloat = 720
  static let rowHeight: CGFloat = 36
  static let verticalPadding: CGFloat = 6
  static let maximumHeight: CGFloat = 400

  /// Extra height for the failure note. An estimate, for the reason the
  /// filter chrome's is.
  static let noticeHeight: CGFloat = 22

  /// The vertical inset the subgroup heading carries on each side. Zero, so
  /// the heading draws exactly one row: a List row adds its insets to its
  /// content height, and anything more would overflow the panel height the
  /// row count computes.
  static let headingVerticalInset: CGFloat = 0

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
    ordering: SearchOrdering = .mru
  ) -> Int {
    let (ordinary, subgroups) = DisplayModes.sections(
      of: windows,
      modes: modes,
      query: query,
      exclusions: exclusions,
      fuzzy: fuzzy,
      ordering: ordering
    )
    let subgroupRows = subgroups.reduce(0) { $0 + $1.1.count }
    return ordinary.count + subgroupRows + subgroups.count
  }

  /// Height for a given number of rows. The panel grows with its content until
  /// the cap, past which the list scrolls instead of the panel growing.
  static func height(rowCount: Int) -> CGFloat {
    height(rowCount: rowCount, for: .standard)
  }

  /// The row height one step draws, in whole points.
  static func rowHeight(for scale: TextScaleLevel) -> CGFloat {
    scale.scaledRowHeight
  }

  /// The content height the subgroup heading draws at one step. One row,
  /// so the heading counts in the panel height exactly as drawn.
  static func headingRowHeight(for scale: TextScaleLevel) -> CGFloat {
    rowHeight(for: scale)
  }

  /// The panel width one step draws, in whole points.
  static func width(for scale: TextScaleLevel) -> CGFloat {
    scale.scaledWidth
  }

  /// Height for a given number of rows at one step. The cap stays put
  /// while the rows grow, so a large step scrolls sooner rather than
  /// outgrowing the screen.
  static func height(rowCount: Int, for scale: TextScaleLevel) -> CGFloat {
    precondition(rowCount >= 0, "rowCount must not be negative")
    return min(CGFloat(rowCount) * rowHeight(for: scale) + verticalPadding * 2, maximumHeight)
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

  /// The full content height at one step: rows plus chrome plus the
  /// note when one shows, capped as one total so a large step never
  /// outgrows the screen.
  static func totalHeight(
    rowCount: Int,
    query: String,
    filterActive: Bool,
    notice: Bool,
    for scale: TextScaleLevel
  ) -> CGFloat {
    var total = height(rowCount: rowCount, for: scale)
      + filterChromeHeight(query: query, filterActive: filterActive, for: scale)
    if notice {
      total += noticeHeight(for: scale)
    }
    return min(total, maximumHeight)
  }

  /// The content size for a row count at one step, so the panel and
  /// its tests take all three numbers from one place.
  static func panelSize(
    rowCount: Int,
    query: String,
    filterActive: Bool,
    notice: Bool,
    for scale: TextScaleLevel
  ) -> CGSize {
    CGSize(
      width: width(for: scale),
      height: totalHeight(
        rowCount: rowCount,
        query: query,
        filterActive: filterActive,
        notice: notice,
        for: scale
      )
    )
  }
}
