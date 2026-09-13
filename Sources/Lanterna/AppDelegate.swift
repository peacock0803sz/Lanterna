import AppKit

// Named rather than left to AppKit's re-export: the two input-monitoring
// calls below live in `CGEvent.h`, not in the Application Services umbrella
// the rest of the permission code in this file reaches through.
import CoreGraphics
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchArguments.Options
    private var hotkeys: HotkeyManager?
    /// Held so the refresh loop can be stopped on the way out. The presenter
    /// holds it too, for reading.
    private var windowList: WindowListStore?
    /// Held so the tap can be taken down on the way out, and so what
    /// `startMonitoringModifiers` builds outlives that call: this holds the
    /// monitor, the monitor holds the tap, and Core Graphics is handed a raw
    /// pointer to that tap which it hands back on every event. Something has
    /// to keep the tap at that address for as long as it is installed, and
    /// this property is the far end of that chain.
    private var monitor: ModifierKeyMonitor?
    /// Held so the deliberate stops can be called off on the way out. Absent
    /// in an ordinary run.
    private var monitorStopTask: Task<Void, Never>?
    private var appNapActivity: NSObjectProtocol?

    /// Takes the options whole rather than one parameter per flag, so a flag
    /// added later reaches here without every caller in between being changed
    /// to carry it.
    init(options: LaunchArguments.Options) {
        self.options = options
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

        // Before the hotkeys are claimed, so that the first pass has a head
        // start on the first press and that press is unlikely to find nothing
        // to show.
        let windowList = makeWindowList()
        self.windowList = windowList

        // The panel is held by the presenter, the presenter by the manager's
        // press handler, and the manager by this delegate.
        let presenter = PanelPresenter(
            surface: panel,
            store: windowList,
            closesOnCommandRelease: { [weak self] in self?.monitor?.isMonitoring ?? false }
        )
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

        startMonitoringModifiers(for: presenter)
        observeFrontmostApplication(presenter)
    }

    /// Puts the modifier tap up and writes down what that achieved.
    ///
    /// Attempted here rather than alongside the panel, because a run that
    /// could claim no hotkey at all exits above, and a tap asked for on the
    /// way out would be a permission prompt for a process about to die.
    ///
    /// The presenter needs to know whether a monitor is running, and the
    /// monitor needs a presenter to tell about a release; that ring is cut by
    /// building the presenter first and handing it a way to ask rather than an
    /// answer. What it asks reaches this monitor the moment there is one, so
    /// there is no window in which the presenter holds a yes that has stopped
    /// being true.
    private func startMonitoringModifiers(for presenter: PanelPresenter) {
        requestInputMonitoringIfNeeded()
        let monitor = ModifierKeyMonitor {
            presenter.handleCommandRelease()
        }
        self.monitor = monitor
        let outcome = monitor.start()
        Diagnostics.writeLine(outcome.summaryLine)
        stopPeriodically(monitor, startedWith: outcome)
    }

    /// Switches the monitor off over and over, on the period the command line
    /// asked for, so that it can be watched putting itself back.
    ///
    /// Nothing happens without the argument, and nothing happens without a
    /// monitor. Those are two different questions and only the first is about
    /// the command line: whether a tap could be made is not known until it is
    /// tried, so an argument given to a run that ends up with none is not a
    /// usage error. It simply has nothing to act on, and says nothing rather
    /// than announcing stops that will never come.
    private func stopPeriodically(
        _ monitor: ModifierKeyMonitor,
        startedWith outcome: ModifierKeyMonitor.StartOutcome
    ) {
        guard let period = options.stopMonitorEvery, outcome.producedATap else { return }
        Diagnostics.writeLine(
            "stopping the modifier monitor every \(period.components.seconds) s "
                + "(\(LaunchArguments.stopMonitorEveryFlag.name))"
        )
        // `weak` for the same reason the monitor's own loop is: this holds the
        // task, so a strong capture would be the pair keeping each other alive
        // through it.
        monitorStopTask = Task { [weak monitor] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: period)
                } catch {
                    // Cancellation is the only way the sleep fails, and it is
                    // how this ends.
                    return
                }
                // Asked again after the wait for the reason the monitor's own
                // loop asks again: a cancellation landing while this turn was
                // already queued does not call it back, and the stop would
                // then be announced after the monitor had been taken down.
                guard !Task.isCancelled else { return }
                guard let monitor else { return }
                monitor.stopOnPurpose()
            }
        }
    }

    /// Puts the input-monitoring dialog in front of the user, once, before a
    /// tap is attempted.
    ///
    /// Asked at launch rather than off the first key press, and for the same
    /// reason `makeWindowList()` settles Accessibility at launch: a system
    /// dialog arriving in answer to a keystroke is a worse thing to explain
    /// than a line in the log saying which way this run went. That also makes
    /// the answer a once-a-launch one — a grant given while the app is running
    /// changes nothing until the next launch.
    ///
    /// Neither answer is branched on. The preflight only says whether a dialog
    /// is worth putting up, and the request comes back as soon as that dialog
    /// is on screen rather than when the user has finished with it — so the
    /// `tapCreate` that follows is asked while the grant is still absent, and
    /// **a first launch without the permission always falls back to closing on
    /// a second press.** Nothing here waits for the grant or re-attempts the
    /// tap when it arrives: a run that changed its mind halfway would close
    /// the panel one way before the grant and another way after it, with
    /// nothing in the log to say when it switched.
    private func requestInputMonitoringIfNeeded() {
        guard !CGPreflightListenEventAccess() else { return }
        // The return value answers the question the line above has already
        // answered. This is called for the dialog it raises, nothing else.
        _ = CGRequestListenEventAccess()
    }

    /// Tells the presenter whenever an application comes to the front, so that
    /// turning to something else puts the panel away.
    ///
    /// Every activation is announced, this process's own included, and sorting
    /// out which of them matters is the presenter's decision rather than this
    /// one's: the delegate would have to know why the panel is up in order to
    /// know which notification should take it down.
    ///
    /// Nothing removes the observation. The token would only be needed to stop
    /// observing, and this observation stops when the process does; the
    /// notification centre holds it in the meantime whether or not anyone
    /// else does. A removal in `applicationWillTerminate` would also run on
    /// only one of the ways this process ends, which is a worse account of
    /// itself than none.
    private func observeFrontmostApplication(_ presenter: PanelPresenter) {
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            else { return }
            // The queue above is the main one, so this is the main actor's
            // executor; nothing weaker than a trap is wanted if that ever
            // stops being true.
            MainActor.assumeIsolated {
                presenter.handleActivation(of: application.processIdentifier)
            }
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
        windowList?.stop()
        // Before the monitor goes, so the last thing done to the tap is taking
        // it down rather than switching it off once more. The order is not on
        // its own enough to promise that: cancelling raises a flag rather than
        // calling back a stop the actor has already been handed, so what makes
        // it hold is the loop asking again after it wakes and giving up there.
        monitorStopTask?.cancel()
        monitorStopTask = nil
        // After the restore above, never before it. The two are not equally
        // recoverable: this tap goes away with the process whatever happens
        // here, while a system shortcut left switched off outlives the process
        // that switched it off. So nothing that could fail is allowed to stand
        // between a launch and that shortcut coming back.
        monitor?.stop()
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

    /// Where the panel's rows come from, and whether they are kept current.
    ///
    /// The choice between fixture, live windows and nothing is made once here
    /// rather than per press, so a permission granted after launch takes
    /// effect only on the next run. Permission in particular is asked for at
    /// launch only: the system's dialog arriving in answer to a key press
    /// would be a worse thing to explain than an empty panel with a reason in
    /// the log.
    private func makeWindowList() -> WindowListStore {
        if let sampleCount = options.sampleCount {
            // The fixture needs no permission, so the check is skipped with
            // it, and it never changes, so nothing refreshes it.
            Diagnostics.writeLine("showing \(sampleCount) sample entries (--sample-count)")
            return WindowListStore(fixed: SampleWindows.make(count: sampleCount))
        }
        guard AccessibilityPermission.isTrusted(promptingIfNeeded: true) else {
            Diagnostics.writeLine(
                "accessibility permission not granted; the window list stays empty for this run; "
                    + "grant it in System Settings > Privacy & Security > Accessibility and "
                    + "restart the app"
            )
            // An empty list is held rather than a loop started, which would
            // report the same missing permission on every pass for as long as
            // the process ran.
            return WindowListStore(fixed: [])
        }
        let store = WindowListStore()
        store.start()
        return store
    }
}
