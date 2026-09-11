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

        panel.present(windows: windows)

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
            // The fixture needs no permission, so the check is skipped with it.
            Diagnostics.writeLine("showing \(sampleCount) sample entries (--sample-count)")
            return SampleWindows.make(count: sampleCount)
        }
        // Asked once per launch. The system shows its own dialog, and the panel
        // still appears, because an empty panel with a reason in the log
        // explains itself better than no panel at all.
        guard AccessibilityPermission.isTrusted(promptingIfNeeded: true) else {
            Diagnostics.writeLine(
                "accessibility permission not granted; the window list is empty until it is "
                    + "granted in System Settings > Privacy & Security > Accessibility"
            )
            return []
        }
        let snapshot = WindowEnumerator().enumerateRegularApplications()
        Diagnostics.writeLine(snapshot.summaryLine)
        return snapshot.items
    }

    /// Logged rather than eyeballed: the launch-to-visible budget is a number.
    /// The reading is taken right after `orderFrontRegardless()`, so it covers
    /// the work up to that call and not the compositing that follows.
    private func reportTimeToOrderFront(entryCount: Int) {
        let elapsed = Diagnostics.millisecondsText(ContinuousClock.now - launchedAt)
        Diagnostics.writeLine("panel ordered front after \(elapsed) ms (\(entryCount) entries)")
    }
}
