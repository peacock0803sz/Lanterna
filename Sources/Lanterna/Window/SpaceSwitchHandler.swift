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
/// so handling records the frontmost window first — a press landing while
/// the pass below is still running sorts the held list at once, and only a
/// record written before the wait reaches that appearance. The read happens
/// as found: a still-settling switch may name the previous application, so
/// handling reads again after the pass and corrects to the settled window
/// when it differs. A wrong optimistic record predates the snapshot, so the
/// next show sweeps it away if the list never held it. Each read is bounded
/// by at most two timed reads (AXFocusedWindowReader.messagingTimeout
/// each), the same bound the activation path accepts by running on the
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

    /// Handles one Space change: records the frontmost window at once, then
    /// asks for a fresh pass, then corrects to the settled window when the
    /// re-read after the pass disagrees. The pass still runs when there is
    /// nothing to record, because the list itself is stale from the switch
    /// either way. Recording before the wait (rather than after it) is what
    /// reaches a press that lands mid-pass; verifying after it is what keeps
    /// an unsettled read from standing as the newest record.
    func handle() async {
        writeLine("space changed; refreshing window list")
        let optimistic = recordFrontmost()
        await store.refreshEventually()
        correctIfSettled(from: optimistic)
    }

    /// Reads the frontmost window and records it the way an activation
    /// would, returning what was recorded so the correction below can tell
    /// a settled switch from one that was still moving.
    private func recordFrontmost() -> (owner: pid_t, windowID: CGWindowID)? {
        guard let frontmost = frontmostProcessIdentifier() else {
            writeLine("space changed; no frontmost application to record")
            return nil
        }
        guard frontmost != ownProcessIdentifier else {
            writeLine("space changed; frontmost is this process")
            return nil
        }
        guard let windowID = reading.focusedWindowID(of: frontmost) else {
            writeLine("space changed; frontmost window could not be read")
            return nil
        }
        // Through the one outside entry, with the read identity riding a
        // fixed reading: the echo guard still applies, and no second
        // accessibility read can answer differently in between.
        recordExternalActivation(
            of: frontmost,
            excluding: ownProcessIdentifier,
            reading: FixedWindowReading(windowID: windowID),
            into: tracker
        )
        return (frontmost, windowID)
    }

    /// Re-reads the frontmost window once the list is fresh and corrects the
    /// optimistic record when the switch has settled elsewhere. An identity
    /// the fresh enumeration never saw is left out rather than recorded; a
    /// re-read matching the optimistic one records nothing further, so a
    /// genuine activation that landed mid-pass keeps its place.
    private func correctIfSettled(from optimistic: (owner: pid_t, windowID: CGWindowID)?) {
        guard let frontmost = frontmostProcessIdentifier(), frontmost != ownProcessIdentifier,
              let windowID = reading.focusedWindowID(of: frontmost),
              optimistic.map({ $0.owner != frontmost || $0.windowID != windowID }) ?? true,
              store.snapshot?.items.contains(where: {
                  $0.id.windowID == windowID && $0.ownerProcessIdentifier == frontmost
              }) == true
        else {
            return
        }
        writeLine("space changed; settled on a different frontmost window")
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
/// observer does. Fixed lists (the fixture, the missing-permission empty
/// list) never change, so no observer is registered for them.
@MainActor
func startObservingSpaceChanges(store: WindowListStore, tracker: MRUTracker) {
    guard store.isLive else { return }
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
