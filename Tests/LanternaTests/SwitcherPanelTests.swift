import AppKit
@testable import Lanterna
import Testing

/// The panel is configured entirely in its initialiser, and `defer: true` means
/// no window-server window is created, so an instance can be inspected without
/// a running application.
@MainActor
struct SwitcherPanelTests {
    private func panel(rowCount: Int = 3) -> SwitcherPanel {
        SwitcherPanel(content: SwitcherView(windows: SampleWindows.make(count: rowCount)))
    }

    @Test func panelIsANonActivatingFloatingOverlay() {
        let panel = panel()
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == .floating)
        #expect(panel.canBecomeKey == false)
        #expect(panel.canBecomeMain == false)
        #expect(panel.hidesOnDeactivate == false)
    }

    @Test func panelJoinsEverySpaceAndStaysOutOfTheWindowCycle() {
        let panel = panel()
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
    }

    @Test(arguments: [0, 3, 30]) func panelSizeFollowsTheContent(rowCount: Int) {
        let panel = panel(rowCount: rowCount)
        let contentRect = panel.contentRect(forFrameRect: panel.frame)
        #expect(contentRect.width == PanelMetrics.width)
        #expect(contentRect.height == PanelMetrics.height(rowCount: rowCount))
    }
}
