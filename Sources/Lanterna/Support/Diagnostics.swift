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
// swiftlint:disable:next no_unchecked_sendable - every mutable state below is guarded by lock
final class DiagnosticLogStore: @unchecked Sendable {

  // MARK: Internal

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

  /// Emits the line and mirrors it as one locked step. Two calls racing
  /// each other still land in stderr and in the mirror in the same order;
  /// anything weaker would let the on-screen log disagree with what was
  /// emitted. Only called with lines the logger already let through, so
  /// the two surfaces cannot drift apart. Tests use `append` directly,
  /// which mirrors without emitting.
  func write(_ message: String) {
    lock.lock()
    defer { lock.unlock() }
    try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
    mirror(message)
  }

  func append(_ message: String) {
    lock.lock()
    defer { lock.unlock() }
    mirror(message)
  }

  func pin(_ summary: String) {
    lock.lock()
    defer { lock.unlock() }
    pinnedSummary = summary
  }

  // MARK: Private

  private let lock = NSLock()
  private var entries = [Diagnostics.LogEntry]()
  private var nextSequence: UInt64 = 0
  private var pinnedSummary: String?

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

}

// MARK: - Diagnostics

/// Developer-facing output of the app.
///
/// Everything goes to stderr so stdout stays free for whatever the process is
/// piped into.
enum Diagnostics {

  // MARK: Internal

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

  /// The logger this process writes through. Wired once by `bootstrap`,
  /// which `main` calls ahead of the first line on the launch path,
  /// before any concurrency starts, so no line goes out unwired and no
  /// lock guards what a single thread sets up.
  // swiftlint:disable:next implicitly_unwrapped_optional - set once by bootstrap before concurrency starts; never nil afterwards
  private(set) nonisolated(unsafe) static var logger: Logger!

  /// The level in force for this process. Read once per launch from the
  /// effective options and set ahead of the first gated line.
  static var threshold: Logger.Level {
    get { logger.logLevel }
    set { logger.logLevel = newValue }
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

  /// Points the logging system at the mirror backend. Called once per
  /// launch, ahead of the first line; never called twice, never moved after.
  /// A second call traps inside the logging system, which is the right
  /// noise for a launch path wired twice.
  static func bootstrap() {
    LoggingSystem.bootstrap { _ in DiagnosticLogHandler(store: store) }
    logger = Logger(label: "lanterna")
    // Holds warnings and above until the effective options say otherwise,
    // so an early line never leans on the logging default.
    logger.logLevel = .warning
  }

  static func writeLine(_ message: String, level: Logger.Level) {
    logger.log(level: level, "\(message)")
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

// MARK: - DiagnosticLogHandler

/// The one backend this run writes through: stderr and the mirror, as one
/// locked step, so the on-screen log cannot disagree with what was emitted.
/// Takes whatever the logger lets through; the threshold lives on the
/// logger rather than here. A future backend (a file, the system log)
/// arrives as another handler beside this one. Locked around the only
/// mutable state, so sharing it across execution contexts stays sound.
// swiftlint:disable:next no_unchecked_sendable - every mutable state below is guarded by lock
final class DiagnosticLogHandler: LogHandler, @unchecked Sendable {

  // MARK: Lifecycle

  init(store: DiagnosticLogStore) {
    self.store = store
  }

  // MARK: Internal

  var metadataProvider: Logger.MetadataProvider? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return providerStorage
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      providerStorage = newValue
    }
  }

  /// Takes all it receives. The logger gates ahead of this call, so a
  /// second opinion here would only double the rule.
  var logLevel: Logger.Level {
    get {
      lock.lock()
      defer { lock.unlock() }
      return acceptedLevel
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      acceptedLevel = newValue
    }
  }

  var metadata: Logger.Metadata {
    get {
      lock.lock()
      defer { lock.unlock() }
      return metadataStorage
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      metadataStorage = newValue
    }
  }

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(event: LogEvent) {
    store.write(event.message.description)
  }

  // MARK: Private

  private let lock = NSLock()
  private let store: DiagnosticLogStore
  private var metadataStorage: Logger.Metadata = [:]
  private var acceptedLevel = Logger.Level.trace
  private var providerStorage: Logger.MetadataProvider?

}
