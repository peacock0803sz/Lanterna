import CoreGraphics
import Darwin

/// Remembers the order windows were used in, so the panel can draw the most
/// recently used first.
///
/// The only state this feature adds, and it never leaves the process: no
/// persistence, no settings, nothing crossing a launch. What moves the order
/// forward is exactly two things — a commit naming a row, and an activation
/// from outside the panel — and both arrive through `record(_:ownerProcessIdentifier:origin:)`,
/// which is the one entry the tests inject through.
///
/// Identity is the window id together with its owner, because the id alone
/// does not survive reuse: a window id handed out again under another process
/// must not merge with the dead record. The window-server id stays the word
/// the diagnostics line prints; the pair is only ever the dictionary key.
struct MRUKey: Hashable, Sendable {
    let windowID: CGWindowID
    let ownerProcessIdentifier: pid_t
}

/// The one remembered use of one window.
///
/// A sequence number and not a clock: only older-versus-newer is ever asked,
/// and a counter needs no clock to inject and no same-instant tie to break.
/// The origin rides on each record so that sweeping the newest one still
/// leaves the next newest able to say where the order came from.
@MainActor
final class MRUTracker {
    /// One remembered use, in a shape the tests can hold.
    struct UsageRecord: Equatable, Sendable {
        let id: WindowItem.Identifier
        let ownerProcessIdentifier: pid_t
        let sequence: UInt64
        let origin: RecordOrigin
        /// When the use was written down. A record missing from a snapshot
        /// younger than this may postdate the snapshot rather than name a
        /// gone window, so the sweep below spares it.
        let recordedAt: ContinuousClock.Instant
    }

    /// How long an activation notice for the just-committed application is
    /// treated as the commit's own echo. The notice arrives tens of
    /// milliseconds after the switch (measured), while the raise it reports
    /// on may still be on its way; a human round-trip back to the same
    /// application takes far longer. One second clears the echo with room
    /// on both sides.
    static let echoWindow: Duration = .seconds(1)

    /// How long a missing record is spared by the sweep. The refresh loop
    /// re-reads the world about every interval below, so a record younger
    /// than twice that may postdate the snapshot being swept against rather
    /// than name a gone window.
    static let sweepGracePeriod: Duration = .seconds(3)

    /// Where one record came from: the panel's own commit, or an activation
    /// that went around it. Kinds never decide order — newest wins whatever
    /// the kind — they only decide the `via` word on the show line.
    enum RecordOrigin: Equatable, Sendable {
        case commit
        case external
    }

    /// What the newest surviving record came from, or nothing when no record
    /// survives. Read after `ordered(_:)`, which is when sweeping has already
    /// happened, so the answer already accounts for it.
    enum NewestSource: Equatable, Sendable {
        case commit
        case external
        case none
    }

    private var records: [MRUKey: UsageRecord] = [:]
    private var nextSequence: UInt64 = 0
    /// What the last swept appearance knew. A record newer than this
    /// predates no snapshot it was swept against: the look finished before
    /// the use happened, so absence proves nothing. Starts where no look
    /// has ever finished, which sweeps like before.
    /// The application the last commit took, and whether its switch has
    /// returned. A notice for the same application is the commit's own
    /// activation coming back — but only once the switch it belongs to has
    /// run its course; until then the entry only says a commit happened.
    private var lastCommit: (owner: pid_t, switchedAt: ContinuousClock.Instant?)?
    private let now: @MainActor () -> ContinuousClock.Instant
    private var lastSweptAsOf: ContinuousClock.Instant?

    init(now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
    }

    /// Writes down one use. Recording the same target twice only moves its
    /// number forward; the order keeps it first either way, which is what
    /// makes a commit followed by its own activation notification harmless.
    func record(
        _ id: WindowItem.Identifier,
        ownerProcessIdentifier: pid_t,
        origin: RecordOrigin
    ) {
        let key = MRUKey(windowID: id.windowID, ownerProcessIdentifier: ownerProcessIdentifier)
        records[key] = UsageRecord(
            id: id,
            ownerProcessIdentifier: ownerProcessIdentifier,
            sequence: nextSequence,
            origin: origin,
            recordedAt: now()
        )
        nextSequence += 1
        if origin == .commit {
            lastCommit = (ownerProcessIdentifier, nil)
        }
    }

    /// Marks the switch belonging to the last commit as returned.
    ///
    /// Called on every path out of the switch, success or failure: what
    /// matters is that the synchronous wait is over, not how it ended. Only
    /// from here does the echo window mean anything — a notice handled
    /// before this ran could not be the commit's own, because handling
    /// anything at all means the switch is no longer holding the turn.
    func noteSwitchReturned() {
        lastCommit?.switchedAt = now()
    }

    // Whether an outside activation of an application is worth writing down.
    //
    // False only for the commit's own echo: the same application as the
    // last commit, inside the echo window, with no other activation in
    // between. Anything else — another application (which also retires the
    // pending echo), or an expired window — records normally, so a genuine
    // return after a detour is never mistaken for the echo.

    func shouldRecordExternal(for ownerProcessIdentifier: pid_t) -> Bool {
        guard let pending = lastCommit else {
            return true
        }
        guard pending.owner == ownerProcessIdentifier else {
            lastCommit = nil
            return true
        }
        guard let switchedAt = pending.switchedAt,
              now() - switchedAt < Self.echoWindow
        else {
            lastCommit = nil
            return true
        }
        lastCommit = nil
        return false
    }

    /// Notes what the coming sweep may assume known.
    ///
    /// Called with the held snapshot's gathering time before every sweep,
    /// so the sweep below can tell a use the look predates from a window
    /// the look should have seen. Until the first note the sweep behaves
    /// like before, so callers that never observe a snapshot keep the old
    /// semantics.
    func noteSnapshotObserved(_ gatheredAt: ContinuousClock.Instant) {
        lastSweptAsOf = gatheredAt
    }

    /// The given rows newest first, sweeping records for rows that are gone.
    ///
    /// Sweeping happens here and nowhere else: once per appearance, against
    /// the snapshot that appearance was given. Rows with no record keep the
    /// input order behind every recorded row; the input arrives in the
    /// store's fixed order, so that is the fixed order kept. Records owned
    /// by skipped applications stay put whatever their age: their rows are
    /// missing because the look missed, not because the windows closed.
    func ordered(_ items: [WindowItem], skipping skippedOwners: Set<pid_t> = []) -> [WindowItem] {
        prune(to: items, sparing: skippedOwners)
        var recorded: [(item: WindowItem, sequence: UInt64)] = []
        var unrecorded: [WindowItem] = []
        for item in items {
            let key = MRUKey(
                windowID: item.id.windowID,
                ownerProcessIdentifier: item.ownerProcessIdentifier
            )
            if let record = records[key] {
                recorded.append((item, record.sequence))
            } else {
                unrecorded.append(item)
            }
        }
        recorded.sort { $0.sequence > $1.sequence }
        return recorded.map(\.item) + unrecorded
    }

    /// Where the newest surviving record came from.
    ///
    /// Read after `ordered(_:)`. Deriving it from the surviving records —
    /// rather than remembering the last write — is what keeps the answer true
    /// across a sweep that took the newest one away.
    var newestSource: NewestSource {
        let newest = records.values.max { $0.sequence < $1.sequence }
        switch newest?.origin {
        case .commit:
            return .commit
        case .external:
            return .external
        case nil:
            return .none
        }
    }

    /// Drops records for rows the list no longer holds.
    ///
    /// The list and not the panel: what counts as gone is decided against the
    /// snapshot one appearance was given, so a record written while that
    /// appearance is up is never swept by it — the next appearance sweeps
    /// against its own, newer snapshot. Two stays of execution: records
    /// owned by skipped applications, and records younger than the sweep
    /// grace period, which may postdate a stale snapshot.
    private func prune(to items: [WindowItem], sparing skippedOwners: Set<pid_t>) {
        let sweptAt = now()
        var live = Set<MRUKey>()
        live.reserveCapacity(items.count)
        for item in items {
            live.insert(
                MRUKey(
                    windowID: item.id.windowID,
                    ownerProcessIdentifier: item.ownerProcessIdentifier
                )
            )
        }
        records = records.filter { entry in
            live.contains(entry.key)
                || skippedOwners.contains(entry.key.ownerProcessIdentifier)
                || lastSweptAsOf.map { entry.value.recordedAt > $0 } ?? false
                || sweptAt - entry.value.recordedAt < Self.sweepGracePeriod
        }
    }
}
