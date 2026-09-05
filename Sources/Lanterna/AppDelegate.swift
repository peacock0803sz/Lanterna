import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchedAt: ContinuousClock.Instant
    private let sampleCount: Int?
    private var panel: SwitcherPanel?
    private var appNapActivity: NSObjectProtocol?

    /// `sampleCount` draws that many fixture entries instead of the windows
    /// that are really open; `nil` lists the live windows.
    init(launchedAt: ContinuousClock.Instant, sampleCount: Int?) {
        self.launchedAt = launchedAt
        self.sampleCount = sampleCount
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        // App Nap suspends idle background processes, and this one sits idle
        // once the panel is up, so the activity is held for the whole run.
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Switcher panel must be drawn without a wake-up delay"
        )

        let windows = windowsToShow()
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

    /// The list the panel is built from.
    ///
    /// Live windows unless `--sample-count` asks for the fixture, which is the
    /// only way to see anything other than what is really open.
    private func windowsToShow() -> [WindowItem] {
        if let sampleCount {
            Diagnostics.writeLine("showing \(sampleCount) sample entries (--sample-count)")
            return SampleWindows.make(count: sampleCount)
        }
        let snapshot = WindowEnumerator().enumerateRegularApplications()
        Diagnostics.writeLine(snapshot.summaryLine)
        return snapshot.items
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
        let elapsed = Diagnostics.millisecondsText(ContinuousClock.now - launchedAt)
        Diagnostics.writeLine("panel ordered front after \(elapsed) ms (\(entryCount) entries)")
    }
}
