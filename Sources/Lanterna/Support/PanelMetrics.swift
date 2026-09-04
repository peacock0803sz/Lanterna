import Foundation

/// Geometry of the switcher panel.
enum PanelMetrics {
    static let width: CGFloat = 680
    static let rowHeight: CGFloat = 36
    static let verticalPadding: CGFloat = 8
    static let maximumHeight: CGFloat = 400

    /// Height for a given number of rows. The panel grows with its content until
    /// the cap, past which the list scrolls instead of the panel growing.
    static func height(rowCount: Int) -> CGFloat {
        precondition(rowCount >= 0, "rowCount must not be negative")
        return min(CGFloat(rowCount) * rowHeight + verticalPadding * 2, maximumHeight)
    }
}
