@testable import Lanterna
import Testing

struct PanelMetricsTests {
    @Test func heightGrowsWithRowCount() {
        #expect(PanelMetrics.height(rowCount: 0) == 16)
        #expect(PanelMetrics.height(rowCount: 1) == 52)
        #expect(PanelMetrics.height(rowCount: 3) == 124)
        #expect(PanelMetrics.height(rowCount: 10) == 376)
    }

    @Test func heightStopsAtTheCap() {
        #expect(PanelMetrics.height(rowCount: 11) == PanelMetrics.maximumHeight)
        #expect(PanelMetrics.height(rowCount: 30) == PanelMetrics.maximumHeight)
    }

    @Test func negativeRowCountsCollapseToPaddingOnly() {
        #expect(PanelMetrics.height(rowCount: -5) == PanelMetrics.height(rowCount: 0))
    }
}
