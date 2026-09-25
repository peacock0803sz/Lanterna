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
/// would be. The record is bounded by at most two timed reads
/// (AXFocusedWindowReader.messagingTimeout each), the same bound the
/// activation path accepts by running on the notification turn.
///
/// Overlapping notifications serialize on the MainActor and the panel sorts
/// at show time, so a transient interleave is harmless; refreshEventually
/// guarantees the snapshot is fresh. The frontmost application is read as
/// found: a still-settling switch may name the previous application, and
/// the next activation then corrects the order.
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

    /// Handles one Space change: records the frontmost window the way an
    /// activation would, then asks for a fresh pass. The pass still runs
    /// when there is nothing to record, because the list itself is stale
    /// from the switch either way.
    func handle() async {
        writeLine("space changed; refreshing window list")
        guard let frontmost = frontmostProcessIdentifier() else {
            writeLine("space changed; no frontmost application to record")
            await store.refreshEventually()
            return
        }
        guard frontmost != ownProcessIdentifier else {
            writeLine("space changed; frontmost is this process")
            await store.refreshEventually()
            return
        }
        recordExternalActivation(
            of: frontmost,
            excluding: ownProcessIdentifier,
            reading: reading,
            into: tracker
        )
        await store.refreshEventually()
    }
}

/// Watches the active Space through SpaceSwitchHandler. Nothing removes
/// the observation: it stops with the process, the way the activation
/// observer does.
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
        Task { @MainActor in
            await handler.handle()
        }
    }
}
