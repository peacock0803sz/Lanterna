import Foundation

/// How much diagnostics one run emits.
///
/// Mirrors the config file values (`"error"`, `"warn"`, `"info"`,
/// `"debug"`) and the `--log-level` words. An absent key means `warn`:
/// unless the file or the command line says otherwise, only warnings
/// and above reach stderr and the on-screen mirror. Ordered so a
/// threshold reads as one comparison: a line shows when its level is
/// at or above the level in force.
enum LogLevel: String, Sendable, Comparable {
    /// Failures that end the run or leave it degraded, and invalid
    /// values. Shown under every threshold.
    case error
    /// Dropped operations and recoverable trouble. Shown by default.
    case warn
    /// The ordinary flow and the timing summaries. Hidden by default.
    case info
    /// The test hook's companions alone. Shown only when asked down to.
    case debug

    /// The order the threshold compares by. Declaration order is the
    /// human reading order rather than a ranking, so the ranking lives
    /// here where a reorder of the cases cannot silently move it.
    private var rank: Int {
        switch self {
        case .error: 0
        case .warn: 1
        case .info: 2
        case .debug: 3
        }
    }

    static func < (left: LogLevel, right: LogLevel) -> Bool {
        left.rank < right.rank
    }

    /// The level one run uses. The command line wins where it says
    /// anything; the file covers the rest; silence on both means `warn`.
    static func effective(cli: LogLevel?, file: LogLevel?) -> LogLevel {
        cli ?? file ?? .warn
    }

    /// Reads one word exactly as written. Only the four lowercase words
    /// count: anything else is for the caller to refuse as a whole.
    static func parse(_ word: String) -> LogLevel? {
        switch word {
        case "error": .error
        case "warn": .warn
        case "info": .info
        case "debug": .debug
        default: nil
        }
    }
}
