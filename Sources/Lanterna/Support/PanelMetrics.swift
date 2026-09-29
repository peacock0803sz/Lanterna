import Foundation

/// Geometry of the switcher panel.
enum PanelMetrics {
    static let width: CGFloat = 680
    static let rowHeight: CGFloat = 36
    static let verticalPadding: CGFloat = 8
    static let maximumHeight: CGFloat = 400

    /// Extra height for the filter chrome: the header whenever filtering is
    /// on, and the query row whenever it reads anything. Estimates, because
    /// SwiftUI lays the rows out: the screenshot check holds them.
    static func filterChromeHeight(query: String, filterActive: Bool) -> CGFloat {
        guard filterActive else { return 0 }
        let header: CGFloat = 28
        return query.isEmpty ? header : header + 34
    }

    /// Extra height for the failure note. An estimate, for the reason the
    /// filter chrome's is.
    static let noticeHeight: CGFloat = 22

    /// How many rows the list draws for these windows under this query:
    /// one for each row it draws, one more for the separator when ordinary
    /// rows stand above non-empty subgroups, and one heading row for each
    /// non-empty subgroup. Split the way the view splits them, so a row the
    /// modes keep out takes no height. The separator is a row of the list
    /// like the others, and the list gives every row at least `rowHeight`.
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
        let separator = (!ordinary.isEmpty && !subgroups.isEmpty) ? 1 : 0
        let subgroupRows = subgroups.reduce(0) { $0 + $1.1.count }
        return ordinary.count + subgroupRows + separator + subgroups.count
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
    /// the note text scales. An estimate, for the reason above.
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
                rowCount: rowCount, query: query,
                filterActive: filterActive, notice: notice, for: scale
            )
        )
    }
}
