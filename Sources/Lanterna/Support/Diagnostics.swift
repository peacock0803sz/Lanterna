import Foundation

/// Developer-facing output of the app.
///
/// Everything goes to stderr so stdout stays free for whatever the process is
/// piped into.
enum Diagnostics {
    static func writeLine(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
    }
}
