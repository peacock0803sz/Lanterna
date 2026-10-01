import Foundation
import Logging

// MARK: - Diagnostics

/// Developer-facing output of the app.
///
/// Everything goes to stderr so stdout stays free for whatever the process is
/// piped into.
enum Diagnostics {

  // MARK: Internal

  /// One line as the handler hands it to the store, before it gets its
  /// number and time.
  struct Record: Equatable, Sendable {
    let level: Logger.Level
    let category: LogCategory
    let message: String
    /// Where the line was written, as `File.swift:123`.
    let source: String
    let context: [String: ContextValue]
  }

  /// One mirrored line: what went to stderr, with when, in what order, and
  /// what kind of line it is.
  ///
  /// Everything but the message is display metadata. It never reaches
  /// stderr, so the emitted lines keep the shape 005 through 007 defined.
  struct LogEntry: Equatable, Sendable {
    /// The run that wrote the line.
    let launch: LaunchID
    /// Increases with every line of one run, from one. Two lines of a run
    /// never share one, and nothing renumbers them.
    let sequence: UInt64
    /// When the line was emitted.
    let capturedAt: Date
    /// One of `error`, `warning`, `info`, `debug`.
    let level: Logger.Level
    let category: LogCategory
    /// The line itself, byte for byte what stderr received.
    let message: String
    /// Where the line was written, as `File.swift:123`.
    let source: String
    let context: [String: ContextValue]
  }

  /// The lowest level the process logger lets through. Every level is
  /// kept: the log window filters what it shows, and nothing is thinned
  /// before it reaches stderr and the mirror.
  static let keptLevel = Logger.Level.debug

  /// This run, named by when it started. `main` reads it first thing, so
  /// the stamp is the start of the process rather than of the first line.
  static let currentLaunch = LaunchID(startedAt: Date(), isCurrent: true)

  /// The logger this process writes through. Wired once by `bootstrap`,
  /// which `main` calls ahead of the first line on the launch path,
  /// before any concurrency starts, so no line goes out unwired and no
  /// lock guards what a single thread sets up.
  // swiftlint:disable:next implicitly_unwrapped_optional - Set once by bootstrap before concurrency starts; never nil afterwards
  private(set) nonisolated(unsafe) static var logger: Logger!

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

  /// The mirrored lines numbered after `sequence`, oldest first.
  static func entries(after sequence: UInt64) -> [LogEntry] {
    store.entries(after: sequence)
  }

  /// Points the logging system at the mirror backend. Called once per
  /// launch, ahead of the first line; never called twice, never moved after.
  /// A second call traps inside the logging system, which is the right
  /// noise for a launch path wired twice.
  static func bootstrap() {
    LoggingSystem.bootstrap { _ in DiagnosticLogHandler(store: store) }
    logger = Logger(label: "lanterna")
    logger.logLevel = keptLevel
  }

  /// Sends one line out with the call site `LogLine` captured, so the
  /// source names the file that wrote it rather than this one.
  static func writeLine(_ line: LogLine) {
    var metadata: Logger.Metadata = [DiagnosticLogHandler.categoryKey: .string(line.category.rawValue)]
    if !line.context.isEmpty {
      metadata[DiagnosticLogHandler.contextKey] = .stringConvertible(ContextBox(values: line.context))
    }
    logger.log(level: line.level, "\(line.message)", metadata: metadata, file: line.file, line: line.line)
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

  // MARK: Private

  /// The store behind the mirror. One per process; the tests hold their own.
  private static let store = DiagnosticLogStore()

}
