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

    /// The separator above the parked rows is one more row, drawn only when
    /// a row is parked.
    @Test @MainActor func theSeparatorCountsAsARowWhenAnyRowIsParked() {
        let windows = SampleWindows.make(count: 3)
        #expect(PanelMetrics.drawnRowCount([]) == 0)
        #expect(PanelMetrics.drawnRowCount(windows) == 3)
        #expect(PanelMetrics.drawnRowCount([windows[0], windows[1].settingMinimized(true)]) == 3)
        #expect(PanelMetrics.drawnRowCount(windows.map { $0.settingHidden(true) }) == 4)
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
