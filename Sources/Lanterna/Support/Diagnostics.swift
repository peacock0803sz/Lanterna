import Foundation
import Logging

// MARK: - DiagnosticLog

/// How many emitted lines the process keeps for the on-screen view.
///
/// A contract value rather than a tuning knob: the view promises the newest
/// entries up to this count, and the tests pin it.
enum DiagnosticLog {
  static let capacity = 500
}

// MARK: - DiagnosticLogStore

/// The mirror itself. Fixed length: past the cap, the oldest lines leave.
///
/// A class of its own rather than static state, so a test can hold one and
/// fill past the cap without a long-lived process or racing other suites.
/// Locked because lines are written from more than one execution context.
// swiftlint:disable:next no_unchecked_sendable - Every mutable state below is guarded by the lock
final class DiagnosticLogStore: @unchecked Sendable {

  // MARK: Lifecycle

  /// `emit` receives exactly what stderr gets; tests pass their own to
  /// read it back.
  init(
    launch: LaunchID = Diagnostics.currentLaunch,
    emit: @escaping @Sendable (String) -> Void = DiagnosticLogStore.standardError
  ) {
    self.launch = launch
    self.emit = emit
  }

  // MARK: Internal

  let launch: LaunchID

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

  /// Writes to the real stderr, the message and a newline only.
  static func standardError(_ text: String) {
    try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
  }

  /// Emits the line and mirrors it as one locked step. Two calls racing
  /// each other still land in stderr and in the mirror in the same order;
  /// anything weaker would let the on-screen log disagree with what was
  /// emitted. Only the message reaches stderr, so its lines keep the shape
  /// they always had. Tests use `append` directly, which mirrors without
  /// emitting.
  func write(_ record: Diagnostics.Record) {
    lock.lock()
    defer { lock.unlock() }
    emit(record.message + "\n")
    mirror(record)
  }

  func append(_ record: Diagnostics.Record) {
    lock.lock()
    defer { lock.unlock() }
    mirror(record)
  }

  func pin(_ summary: String) {
    lock.lock()
    defer { lock.unlock() }
    pinnedSummary = summary
  }

  // MARK: Private

  private let lock = NSLock()
  private let emit: @Sendable (String) -> Void
  private var entries = [Diagnostics.LogEntry]()
  /// Numbers start at one, as people count rows.
  private var nextSequence: UInt64 = 1
  private var pinnedSummary: String?

  /// Adds one line under the caller's lock.
  private func mirror(_ record: Diagnostics.Record) {
    entries.append(Diagnostics.LogEntry(
      launch: launch,
      sequence: nextSequence,
      capturedAt: Date(),
      level: record.level,
      category: record.category,
      message: record.message,
      source: record.source,
      context: record.context
    ))
    nextSequence += 1
    if entries.count > DiagnosticLog.capacity {
      entries.removeFirst(entries.count - DiagnosticLog.capacity)
    }
  }

}

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
