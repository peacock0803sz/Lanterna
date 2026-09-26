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
        query: String = ""
    ) -> Int {
        let (ordinary, subgroups) = DisplayModes.sections(of: windows, modes: modes, query: query)
        let separator = (!ordinary.isEmpty && !subgroups.isEmpty) ? 1 : 0
        let subgroupRows = subgroups.reduce(0) { $0 + $1.1.count }
        return ordinary.count + subgroupRows + separator + subgroups.count
    }

    /// Height for a given number of rows. The panel grows with its content until
    /// the cap, past which the list scrolls instead of the panel growing.
    static func height(rowCount: Int) -> CGFloat {
        precondition(rowCount >= 0, "rowCount must not be negative")
        return min(CGFloat(rowCount) * rowHeight + verticalPadding * 2, maximumHeight)
    }
}
