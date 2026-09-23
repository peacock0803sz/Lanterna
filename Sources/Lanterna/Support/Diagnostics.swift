import Foundation

/// How many emitted lines the process keeps for the on-screen view.
///
/// A contract value rather than a tuning knob: the view promises the newest
/// entries up to this count, and the tests pin it.
enum DiagnosticLog {
    static let capacity = 500
}

/// The mirror itself. Fixed length: past the cap, the oldest lines leave.
///
/// A class of its own rather than static state, so a test can hold one and
/// fill past the cap without a long-lived process or racing other suites.
/// Locked because lines are written from more than one execution context.
final class DiagnosticLogStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Diagnostics.LogEntry] = []
    private var nextSequence: UInt64 = 0
    private var pinnedSummary: String?

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(
            Diagnostics.LogEntry(sequence: nextSequence, capturedAt: Date(), message: message)
        )
        nextSequence += 1
        if entries.count > DiagnosticLog.capacity {
            entries.removeFirst(entries.count - DiagnosticLog.capacity)
        }
    }

    var recent: [Diagnostics.LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    var summary: String? {
        lock.lock()
        defer { lock.unlock() }
        return pinnedSummary
    }

    func pin(_ summary: String) {
        lock.lock()
        defer { lock.unlock() }
        pinnedSummary = summary
    }
}

/// Developer-facing output of the app.
///
/// Everything goes to stderr so stdout stays free for whatever the process is
/// piped into.
enum Diagnostics {
    /// One mirrored line: what went to stderr, with when and in what order.
    ///
    /// The time and the number are display metadata only. They never reach
    /// stderr, so the emitted lines keep the shape 005 through 007 defined.
    struct LogEntry: Equatable, Sendable {
        /// Increases with every line. Two lines never share one.
        let sequence: UInt64
        /// When the line was emitted.
        let capturedAt: Date
        /// The line itself, byte for byte what stderr received.
        let message: String
    }

    /// The store behind the mirror. One per process; the tests hold their own.
    private static let store = DiagnosticLogStore()

    static func writeLine(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
        store.append(message)
    }

    /// The mirrored lines, oldest first. Never longer than
    /// `DiagnosticLog.capacity`.
    static var recentEntries: [LogEntry] {
        store.recent
    }

    /// The launch summary, pinned outside the ring. A long run must not push
    /// the startup outcome and the permission state off the view.
    static var launchSummary: String? {
        store.summary
    }

    /// Pins the launch summary. Called once per launch; later calls replace it.
    static func pinLaunchSummary(_ summary: String) {
        store.pin(summary)
    }

    /// A duration in milliseconds, one decimal place.
    ///
    /// `%.1f` rather than a `FormatStyle`: a developer log line must read the
    /// same in every locale, and a formatted number would switch decimal and
    /// grouping separators.
    static func millisecondsText(_ duration: Duration) -> String {
        let milliseconds = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) * 1e-15
        return String(format: "%.1f", milliseconds)
    }
}
