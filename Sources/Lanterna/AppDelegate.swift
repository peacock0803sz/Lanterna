import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchedAt: ContinuousClock.Instant
    private let sampleCount: Int?
    private var panel: SwitcherPanel?
    private var appNapActivity: NSObjectProtocol?

    /// `sampleCount` overrides the number of fixture entries; `nil` uses the
    /// standard fixture.
    init(launchedAt: ContinuousClock.Instant, sampleCount: Int?) {
        self.launchedAt = launchedAt
        self.sampleCount = sampleCount
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        // App Nap suspends idle background processes, and this one is idle
        // between invocations, so the activity is held for the whole run.
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Switcher panel must be drawn without a wake-up delay"
        )

        let windows = if let sampleCount {
            SampleWindows.make(count: sampleCount)
        } else {
            SampleWindows.standard()
        }
        // The delegate holds the panel because nothing else does: a panel that
        // is only ordered front would be deallocated.
        let panel = SwitcherPanel(content: SwitcherView(windows: windows))
        self.panel = panel

        centerOnMainDisplay(panel)
        panel.orderFrontRegardless()

        reportTimeToOrderFront(entryCount: windows.count)
    }

    func applicationWillTerminate(_: Notification) {
        if let appNapActivity {
            ProcessInfo.processInfo.endActivity(appNapActivity)
        }
    }

    /// `NSWindow.center()` centres on whichever screen the window already sits
    /// on, so the display is picked explicitly. `NSScreen.screens.first` is the
    /// display that carries the menu bar, which is the main display the spec
    /// asks for; `NSScreen.main` would instead follow the key window and so
    /// could be any display.
    private func centerOnMainDisplay(_ panel: SwitcherPanel) {
        guard let area = NSScreen.screens.first?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        )
    }

    /// Logged rather than eyeballed: the launch-to-visible budget is a number.
    /// The reading is taken right after `orderFrontRegardless()`, so it covers
    /// the work up to that call and not the compositing that follows.
    private func reportTimeToOrderFront(entryCount: Int) {
        let elapsed = ContinuousClock.now - launchedAt
        let milliseconds = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) * 1e-15
        let elapsedText = milliseconds.formatted(.number.precision(.fractionLength(1)))
        Diagnostics.writeLine("panel ordered front after \(elapsedText) ms (\(entryCount) entries)")
    }
}
