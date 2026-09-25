import AppKit
import CoreGraphics
import Darwin

/// Refreshes the held list and the most-recently-used order when the active
/// Space changes.
///
/// A Space switch does not always post an application activation, so neither
/// the polling loop nor the activation observer moves fast enough on its own:
/// the first open after the switch would sort on the pre-switch memory until
/// the next pass replaces it. The notification itself names no application,
/// so handling asks for a fresh pass first and then reads the frontmost
/// window, recording it the way an activation would — but only when the
/// refreshed list actually holds it. A still-settling switch may name the
/// previous application; such a guess must never become the newest record,
/// so an identity the fresh enumeration did not see is left out while the
/// refreshed list still lands. The single accessibility read is bounded by
/// at most two timed reads (AXFocusedWindowReader.messagingTimeout each),
/// the same bound the activation path accepts by running on the
/// notification turn.
///
/// Overlapping notifications serialize on the MainActor and the panel sorts
/// at show time, so a transient interleave is harmless; refreshEventually
/// does not return until the list is fresh (unless the loop was stopped).
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

    /// Handles one Space change: asks for a fresh pass first, then records
    /// the frontmost window the way an activation would — but only when the
    /// refreshed list holds it. The pass still runs when there is nothing
    /// to record, because the list itself is stale from the switch either
    /// way. Refreshing first also narrows the unsettled-switch race to the
    /// read that follows the pass instead of the one preceding it.
    func handle() async {
        writeLine("space changed; refreshing window list")
        await store.refreshEventually()
        guard let frontmost = frontmostProcessIdentifier() else {
            writeLine("space changed; no frontmost application to record")
            return
        }
        guard frontmost != ownProcessIdentifier else {
            writeLine("space changed; frontmost is this process")
            return
        }
        guard let windowID = reading.focusedWindowID(of: frontmost),
              store.snapshot?.items.contains(where: {
                  $0.id.windowID == windowID && $0.ownerProcessIdentifier == frontmost
              }) == true
        else {
            writeLine("space changed; frontmost window not in the refreshed list")
            return
        }
        // Through the one outside entry, with the verified identity riding
        // a fixed reading: the echo guard still applies, and no second
        // accessibility read can answer differently in between.
        recordExternalActivation(
            of: frontmost,
            excluding: ownProcessIdentifier,
            reading: FixedWindowReading(windowID: windowID),
            into: tracker
        )
    }
}

/// Answers one window identity for any process, carrying an identity that
/// was already read and verified elsewhere through the recording entry.
private struct FixedWindowReading: FocusedWindowReading {
    let windowID: CGWindowID?
    func focusedWindowID(of _: pid_t) -> CGWindowID? {
        windowID
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
