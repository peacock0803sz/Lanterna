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
    private var thresholdLevel: LogLevel = .warn

    /// The level in force. Set once per launch, ahead of the first line.
    var threshold: LogLevel {
        get {
            lock.lock()
            defer { lock.unlock() }
            return thresholdLevel
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            thresholdLevel = newValue
        }
    }

    /// Emits the line and mirrors it as one locked step. Two calls racing
    /// each other still land in stderr and in the mirror in the same order;
    /// anything weaker would let the on-screen log disagree with what was
    /// emitted. Tests use `append` directly, which mirrors without emitting.
    ///
    /// Lines below the threshold go nowhere: neither to stderr nor to the
    /// mirror, and they spend none of the capacity. The filtering happens
    /// here, at emit time, so the two surfaces cannot drift apart.
    /// A line shows when the threshold reaches it: warnings cover errors
    /// but not the ordinary flow, and errors alone cover nothing else.
    func write(_ message: String, level: LogLevel) {
        lock.lock()
        defer { lock.unlock() }
        guard thresholdLevel >= level else { return }
        try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
        mirror(message)
    }

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        mirror(message)
    }

    /// Adds one line under the caller's lock.
    private func mirror(_ message: String) {
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

    /// The level in force for this process. Read once per launch from the
    /// effective options and set ahead of the first line; never moved after.
    static var threshold: LogLevel {
        get { store.threshold }
        set { store.threshold = newValue }
    }

    static func writeLine(_ message: String, level: LogLevel) {
        store.write(message, level: level)
    }

    /// The compatibility road for emission sites not yet carrying a level.
    /// Routes at warnings so unconverted lines stay visible while the
    /// conversion moves file by file. Removed once every site is explicit.
    static func writeLine(_ message: String) {
        store.write(message, level: .warn)
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
