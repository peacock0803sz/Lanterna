import Foundation
@testable import Lanterna
import Testing

struct PanelMetricsTests {
    @Test func heightGrowsWithRowCount() {
        // One literal pin on the contract, so changing a constant fails here
        // and not only inside the formula the other cases share.
        #expect(PanelMetrics.height(rowCount: 3) == 124)

        for rowCount in [0, 1, 3, 10] {
            let expected = CGFloat(rowCount) * PanelMetrics.rowHeight
                + 2 * PanelMetrics.verticalPadding
            #expect(PanelMetrics.height(rowCount: rowCount) == expected)
        }
    }

    /// The separator above the subgroups is one more row, drawn only when
    /// ordinary rows stand above them, and each non-empty subgroup carries
    /// one heading row.
    @Test @MainActor func theSeparatorCountsAsARowWhenAnyRowIsParked() {
        let windows = SampleWindows.make(count: 3)
        #expect(PanelMetrics.drawnRowCount([]) == 0)
        #expect(PanelMetrics.drawnRowCount(windows) == 3)
        #expect(PanelMetrics.drawnRowCount([windows[0], windows[1].settingMinimized(true)]) == 4)
        #expect(PanelMetrics.drawnRowCount(windows.map { $0.settingHidden(true) }) == 4)
    }

    /// Each non-empty subgroup carries one heading row, and the separator
    /// only divides when ordinary rows stand above the subgroups.
    @Test @MainActor func subgroupsAndHeadingsCountAsRows() {
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
        #expect(PanelMetrics.drawnRowCount(mixed, modes: .defaults) == 4)
        let twoGroups = [
            windows[0].settingMinimized(true),
            windows[1].settingHidden(true),
        ]
        #expect(PanelMetrics.drawnRowCount(twoGroups, modes: .defaults) == 4)
    }

    @Test func widthIsFixedByTheUIContract() {
        #expect(PanelMetrics.width == 680)
    }

    @Test func heightStopsAtTheCap() {
        #expect(PanelMetrics.maximumHeight == 400)
        #expect(PanelMetrics.height(rowCount: 11) == PanelMetrics.maximumHeight)
        #expect(PanelMetrics.height(rowCount: 30) == PanelMetrics.maximumHeight)
    }
}
