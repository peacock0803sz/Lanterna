import AppKit
import Darwin

/// Refreshes the held list and the most-recently-used order when the active
/// Space changes.
///
/// A Space switch does not always post an application activation, so neither
/// the polling loop nor the activation observer moves fast enough on its own:
/// the first open after the switch would sort on the pre-switch memory until
/// the next pass replaces it. The notification itself names no application,
/// so the frontmost one is read here and recorded the way an activation
/// would be. Recording runs before the refresh because the refresh can take
/// a second behind a wedged application while the record is bounded by the
/// messaging timeout.
@MainActor
struct SpaceSwitchHandler {
    private let store: WindowListStore
    private let tracker: MRUTracker
    private let ownProcessIdentifier: pid_t
    private let frontmostProcessIdentifier: @MainActor () -> pid_t?
    private let reading: any FocusedWindowReading
    private let writeLine: @MainActor (String) -> Void

    init(
        store: WindowListStore,
        tracker: MRUTracker,
        ownProcessIdentifier: pid_t,
        frontmostProcessIdentifier: @escaping @MainActor () -> pid_t?,
        reading: any FocusedWindowReading,
        writeLine: @escaping @MainActor (String) -> Void
    ) {
        self.store = store
        self.tracker = tracker
        self.ownProcessIdentifier = ownProcessIdentifier
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
        self.reading = reading
        self.writeLine = writeLine
    }

    func handle() async {
        writeLine("space changed; refreshing window list")
        if let frontmost = frontmostProcessIdentifier() {
            recordExternalActivation(
                of: frontmost,
                excluding: ownProcessIdentifier,
                reading: reading,
                into: tracker
            )
        }
        await store.refresh()
    }
}

/// Watches the active Space and refreshes the held list and the
/// most-recently-used order when it changes.
///
/// A Space switch does not always activate an application, so the activation
/// observer misses it and the first open after the switch would sort on the
/// pre-switch memory until the next poll pass. The notification names no
/// application, so the handler reads the frontmost one itself. Nothing
/// removes the observation: it stops with the process, the way the
/// activation observer does.
@MainActor
func startObservingSpaceChanges(store: WindowListStore, tracker: MRUTracker) {
    let handler = SpaceSwitchHandler(
        store: store,
        tracker: tracker,
        ownProcessIdentifier: getpid(),
        frontmostProcessIdentifier: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        reading: AXFocusedWindowReader(),
        writeLine: Diagnostics.writeLine
    )
    _ = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        MainActor.assumeIsolated {
            Task {
                await handler.handle()
            }
        }
    }
}
