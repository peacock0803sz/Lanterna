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
    }

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
            origin: origin
        )
        nextSequence += 1
    }

    /// The given rows newest first, sweeping records for rows that are gone.
    ///
    /// Sweeping happens here and nowhere else: once per appearance, against
    /// the snapshot that appearance was given. Rows with no record keep the
    /// input order behind every recorded row; the input arrives in the
    /// store's fixed order, so that is the fixed order kept.
    func ordered(_ items: [WindowItem]) -> [WindowItem] {
        prune(to: items)
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
    /// against its own, newer snapshot.
    private func prune(to items: [WindowItem]) {
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
        records = records.filter { live.contains($0.key) }
    }
}
