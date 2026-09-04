import AppKit
@testable import Lanterna
import Testing

/// The panel is configured entirely in its initialiser, and `defer: true` means
/// no window-server window is created, so an instance can be inspected without
/// a running application.
@MainActor
struct SwitcherPanelTests {
    @Test func panelIsANonActivatingFloatingOverlay() {
        let panel = SwitcherPanel(rowCount: 3)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == .floating)
        #expect(panel.canBecomeKey == false)
        #expect(panel.canBecomeMain == false)
        #expect(panel.hidesOnDeactivate == false)
    }

    @Test func panelJoinsEverySpaceAndStaysOutOfTheWindowCycle() {
        let panel = SwitcherPanel(rowCount: 3)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
    }

    @Test(arguments: [0, 3, 30]) func panelSizeFollowsTheRowCount(rowCount: Int) {
        let panel = SwitcherPanel(rowCount: rowCount)
        let contentRect = panel.contentRect(forFrameRect: panel.frame)
        #expect(contentRect.width == PanelMetrics.width)
        #expect(contentRect.height == PanelMetrics.height(rowCount: rowCount))
    }
}
