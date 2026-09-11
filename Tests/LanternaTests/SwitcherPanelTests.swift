import AppKit
@testable import Lanterna
import Testing

/// `defer: true` means no window-server window is created, so an instance can
/// be inspected — and driven through `update(windows:)` — without a running
/// application.
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

    /// The height has to follow a swapped-in list as closely as it follows the
    /// one the panel was built with, because from the second appearance on it
    /// is the only thing setting the size.
    @Test(arguments: [0, 1, 3, 30]) func updatedSizeFollowsTheNewContent(rowCount: Int) {
        let panel = panel(rowCount: 5)
        panel.update(windows: SampleWindows.make(count: rowCount))
        let contentRect = panel.contentRect(forFrameRect: panel.frame)
        #expect(contentRect.width == PanelMetrics.width)
        #expect(contentRect.height == PanelMetrics.height(rowCount: rowCount))
    }

    /// Swapping the list must not cost a new hosting view: rebuilding the view
    /// tree on every appearance is exactly what keeping one panel avoids.
    @Test func updateKeepsTheHostingViewItAlreadyHas() {
        let panel = panel()
        let before = panel.contentView
        panel.update(windows: SampleWindows.make(count: 7))
        #expect(panel.contentView === before)
    }

    /// Nothing moves the panel between appearances, so a display change leaves
    /// a panel that is up wherever the old arrangement put it. Only the
    /// putting back is pinned here; what was seen when a panel was left where
    /// it fell is recorded on `screensChanged()`, and is not something a test
    /// can arrange.
    @Test func aPanelThatIsUpIsPutBackWhenTheScreensChange() {
        let panel = panel()
        panel.present(windows: SampleWindows.make(count: 3))
        let belongs = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: belongs.x + 400, y: belongs.y + 200))

        panel.screensChanged()

        #expect(panel.frame.origin == belongs)
        panel.dismiss()
    }

    /// A panel that is not up is put in its place by the next appearance, and
    /// this runs whenever anyone plugs in a display.
    @Test func aPanelThatIsDownIsLeftAloneWhenTheScreensChange() {
        let panel = panel()
        panel.setFrameOrigin(NSPoint(x: 17, y: 23))
        panel.screensChanged()
        #expect(panel.frame.origin == NSPoint(x: 17, y: 23))
    }

    /// `aPanelThatIsUpIsPutBackWhenTheScreensChange` calls `screensChanged()`
    /// itself, which says only that the method does its job once something
    /// calls it. This says that something does. The subscription is made in
    /// `init` and nothing else in the app reaches it, so registering the wrong
    /// notification name or dropping the block would leave the method correct
    /// and never called, and a panel that is up when the displays are
    /// rearranged would stay wherever the old arrangement put it.
    ///
    /// The block is handed to `OperationQueue.main` rather than run on the
    /// thread that posts, so the assertion has to give the main queue its turn
    /// before reading the frame back. Yielding does that without waiting on a
    /// clock; the count is slack, not a measurement.
    @Test func aDisplayChangeNotificationPutsThePanelBack() async {
        let panel = panel()
        panel.present(windows: SampleWindows.make(count: 3))
        let belongs = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: belongs.x + 400, y: belongs.y + 200))

        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(panel.frame.origin == belongs)
        panel.dismiss()
    }
}
