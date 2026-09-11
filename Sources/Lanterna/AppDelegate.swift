import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sampleCount: Int?
    private var hotkeys: HotkeyManager?
    private var appNapActivity: NSObjectProtocol?

    /// `sampleCount` draws that many fixture entries instead of the windows
    /// that are really open; `nil` lists the live windows.
    init(sampleCount: Int?) {
        self.sampleCount = sampleCount
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        // App Nap suspends idle background processes, and this one sits idle
        // between presses, so the activity is held for the whole run.
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Switcher panel must be drawn without a wake-up delay"
        )

        // Built now and left off screen. Nothing shows until a key is pressed,
        // and building the window ahead of time keeps its cost off the path
        // between that press and the panel.
        let panel = SwitcherPanel(content: SwitcherView(windows: []))

        // The panel is held by the presenter, the presenter by the manager's
        // press handler, and the manager by this delegate.
        let presenter = PanelPresenter(surface: panel, gather: windowSource())
        let hotkeys = HotkeyManager { combination, deliveryDelay in
            presenter.handleHotkey(combination, deliveryDelay: deliveryDelay)
        }
        self.hotkeys = hotkeys

        let outcome = hotkeys.register()
        Diagnostics.writeLine(outcome.summaryLine)
        guard !outcome.isTotalFailure else {
            // Nothing has been taken from the system yet, so there is nothing
            // to give back on the way out.
            exit(EX_UNAVAILABLE)
        }

        // Armed before the system is touched rather than after. Everything
        // below leaves the machine without its Cmd+Tab until this process puts
        // it back, and a Ctrl+C landing in between would be exactly the case
        // this is here for.
        TerminationSignals.install(cleanUp: shutDown)

        if let line = SystemSwitcherShortcuts.summaryLine(
            disabling: SystemSwitcherShortcuts.disable(outcome.registered)
        ) {
            Diagnostics.writeLine(line)
        }
    }

    func applicationWillTerminate(_: Notification) {
        shutDown()
    }

    /// Gives back everything the launch took, in that order: the system's own
    /// shortcuts first, so they return even if what follows does not.
    ///
    /// Reached twice over, once through the usual termination callback and
    /// once from a caught signal, which exits before that callback can run.
    ///
    /// May end the process rather than return, when the system's shortcuts
    /// could not be given back.
    private func shutDown() {
        let restoreFailures = SystemSwitcherShortcuts.restore()
        if let line = SystemSwitcherShortcuts.summaryLine(restoring: restoreFailures) {
            Diagnostics.writeLine(line)
        }
        hotkeys?.unregister()
        if let appNapActivity {
            ProcessInfo.processInfo.endActivity(appNapActivity)
            self.appNapActivity = nil
        }

        // Reaching this exit means the process could not leave the machine
        // with both shortcuts on, and the diagnostics line saying so is easy
        // to miss in a way an exit status is not. The one that would not go
        // back on may well be off, left that way by an earlier run that was
        // killed, and the write that would have fixed it is the one that
        // failed. Both paths that reach here are the end of the process
        // anyway: the caught-signal path exits as soon as this returns, and
        // all this changes is the status it reports, while the
        // termination-callback path gives up AppKit's remaining teardown,
        // which is no loss when the windows and the run loop are going away
        // with the process regardless. The code differs from the
        // `EX_UNAVAILABLE` used at launch so the two cases stay apart.
        if !restoreFailures.isEmpty {
            exit(EX_OSERR)
        }
    }

    /// Where the panel's rows will come from on every press.
    ///
    /// The choice between fixture, live windows and nothing is made once here
    /// rather than per press, so a permission granted after launch takes
    /// effect only on the next run. Permission in particular is asked for at
    /// launch only: the system's dialog arriving in answer to a key press
    /// would be a worse thing to explain than an empty panel with a reason in
    /// the log.
    private func windowSource() -> @MainActor () -> [WindowItem] {
        if let sampleCount {
            // The fixture needs no permission, so the check is skipped with it.
            Diagnostics.writeLine("showing \(sampleCount) sample entries (--sample-count)")
            let fixture = SampleWindows.make(count: sampleCount)
            return { fixture }
        }
        guard AccessibilityPermission.isTrusted(promptingIfNeeded: true) else {
            Diagnostics.writeLine(
                "accessibility permission not granted; the window list stays empty for this run; "
                    + "grant it in System Settings > Privacy & Security > Accessibility and "
                    + "restart the app"
            )
            return { [] }
        }
        return {
            let snapshot = WindowEnumerator().enumerateRegularApplications()
            Diagnostics.writeLine(snapshot.summaryLine)
            return snapshot.items
        }
    }
}
