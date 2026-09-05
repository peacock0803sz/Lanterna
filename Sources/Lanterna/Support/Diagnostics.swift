import Foundation

/// Developer-facing output of the app.
///
/// Everything goes to stderr so stdout stays free for whatever the process is
/// piped into.
enum Diagnostics {
    static func writeLine(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
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
