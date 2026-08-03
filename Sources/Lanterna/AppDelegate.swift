import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchedAt: ContinuousClock.Instant
    private var panel: SwitcherPanel?
    private var appNapActivity: NSObjectProtocol?

    init(launchedAt: ContinuousClock.Instant) {
        self.launchedAt = launchedAt
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        // The switcher has to answer a hotkey immediately, so the process must
        // never be put to sleep between invocations.
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Switcher must respond to the hotkey without a wake-up delay"
        )

        let windows = sampleWindows()
        // Built once and retained: later steps show and hide this same panel
        // instead of creating a new one per invocation.
        let panel = SwitcherPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PanelMetrics.width,
                height: PanelMetrics.height(rowCount: windows.count)
            )
        )
        panel.contentView = NSHostingView(rootView: SwitcherView(windows: windows))
        self.panel = panel

        centerOnMainDisplay(panel)
        panel.orderFrontRegardless()

        reportTimeToVisible()
    }

    func applicationWillTerminate(_: Notification) {
        if let appNapActivity {
            ProcessInfo.processInfo.endActivity(appNapActivity)
        }
    }

    /// `--sample-count N` swaps the fixture for N entries so panel sizing can be
    /// checked without editing the fixture the tests assert on.
    private func sampleWindows() -> [WindowItem] {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--sample-count") else {
            return SampleWindows.standard()
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex, let count = Int(arguments[valueIndex]) else {
            return SampleWindows.standard()
        }
        return SampleWindows.make(count: count)
    }

    /// `NSWindow.center()` centres on whichever screen the window already sits
    /// on, so the main display is chosen explicitly instead.
    private func centerOnMainDisplay(_ panel: SwitcherPanel) {
        guard let area = NSScreen.main?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        )
    }

    /// Logged rather than eyeballed: the launch-to-visible budget is a number.
    /// Written to stderr so it appears immediately even when the app is launched
    /// detached with its output redirected to a file.
    private func reportTimeToVisible() {
        let elapsed = ContinuousClock.now - launchedAt
        let milliseconds = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) * 1e-15
        let line = String(format: "panel visible after %.1f ms\n", milliseconds)
        FileHandle.standardError.write(Data(line.utf8))
    }
}
