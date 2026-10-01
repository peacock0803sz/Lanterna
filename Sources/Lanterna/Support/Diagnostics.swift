import DuckDB
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

  // MARK: Internal

  /// Runs after the mirror fills, outside the lock, so a slow
  /// consumer never blocks emitting. Set once per launch before
  /// concurrency starts; read on every write after that.
  var onMirror: ((Diagnostics.LogEntry) -> Void)?

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
    let entry: Diagnostics.LogEntry
    let hook: ((Diagnostics.LogEntry) -> Void)?
    lock.lock()
    try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
    entry = mirror(message, level: .info, category: nil, payloadJSON: nil)
    hook = onMirror
    lock.unlock()
    hook?(entry)
  }

  /// Emits a structured line: the message goes to stderr exactly as
  /// given, while the level, grouping, and extra context ride
  /// alongside in the mirror only.
  func write(_ message: String, level: Logger.Level, metadata: Logger.Metadata) {
    let entry: Diagnostics.LogEntry
    let hook: ((Diagnostics.LogEntry) -> Void)?
    lock.lock()
    try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
    entry = mirror(message, level: level, category: metadata.category, payloadJSON: metadata.payloadJSON)
    hook = onMirror
    lock.unlock()
    hook?(entry)
  }

  func append(_ message: String) {
    let entry: Diagnostics.LogEntry
    let hook: ((Diagnostics.LogEntry) -> Void)?
    lock.lock()
    entry = mirror(message, level: .info, category: nil, payloadJSON: nil)
    hook = onMirror
    lock.unlock()
    hook?(entry)
  }

  /// Records a line that must not leave the process: no stderr echo
  /// and no spill. Used for failures of the spill path itself, where
  /// emitting would recurse back into the failing writer.
  func remember(_ message: String, level: Logger.Level) {
    lock.lock()
    defer { lock.unlock() }
    _ = mirror(message, level: level, category: nil, payloadJSON: nil)
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
  private func mirror(
    _ message: String,
    level: Logger.Level,
    category: String?,
    payloadJSON: String?
  ) -> Diagnostics.LogEntry {
    let entry = Diagnostics.LogEntry(
      sequence: nextSequence,
      capturedAt: Foundation.Date(),
      message: message,
      level: level,
      category: category,
      payloadJSON: payloadJSON
    )
    entries.append(entry)
    nextSequence += 1
    if entries.count > DiagnosticLog.capacity {
      entries.removeFirst(entries.count - DiagnosticLog.capacity)
    }
    return entry
  }

}

// MARK: - Diagnostics

/// Developer-facing output of the app.
///
/// Everything goes to stderr so stdout stays free for whatever the process is
/// piped into.
enum Diagnostics {

  // MARK: Internal

  /// One mirrored line: what went to stderr, with when and in what order,
  /// plus the fields the views filter on. The time, the number, and the
  /// extra fields are display metadata only. They never reach stderr,
  /// so the emitted lines keep the shape 005 through 007 defined.
  struct LogEntry: Equatable, Sendable {
    /// Increases with every line. Two lines never share one.
    let sequence: UInt64
    /// When the line was emitted.
    let capturedAt: Foundation.Date
    /// The line itself, byte for byte what stderr received.
    let message: String
    /// How severe the line is. Mirrors the logger words.
    let level: Logger.Level
    /// Where the line comes from, when the caller said so.
    let category: String?
    /// Extra context as JSON text. Absent when the caller attached none.
    let payloadJSON: String?
  }

  /// The logger this process writes through. Wired once by `bootstrap`,
  /// which `main` calls ahead of the first line on the launch path,
  /// before any concurrency starts, so no line goes out unwired and no
  /// lock guards what a single thread sets up.
  // swiftlint:disable:next implicitly_unwrapped_optional - Set once by bootstrap before concurrency starts; never nil afterwards
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

  /// Records a spill-path failure where it stays visible: in the
  /// mirror only, without echoing or spilling.
  static func mirrorSpillFailure(_ message: String) {
    store.remember(message, level: .warning)
  }

  /// Starts spilling mirrored lines to the store. Called once per
  /// launch from the main thread ahead of the run loop, before any
  /// concurrency starts. The current window keeps reading the
  /// mirror, so nothing on screen changes.
  static func startSpilling(
    applicationSupport: URL,
    launchID: String = UUID().uuidString,
    buildVersion: String = AppVersion.full,
    rotation: LogRotation = .daily,
    persist: Bool = true
  ) {
    let origin = LogPersistence.currentOrigin()
    let startedAt = Int64(Foundation.Date().timeIntervalSince1970 * 1000)
    do {
      let spill: ([DiagnosticRow]) throws -> Void
      if persist {
        let directory = LogPersistence.directory(applicationSupport: applicationSupport, origin: origin)
        let launch = LogLaunchStore(
          directory: directory,
          launchID: launchID,
          origin: origin,
          buildVersion: buildVersion,
          startedAtMilliseconds: startedAt,
          rotation: rotation
        )
        launchStore = launch
        spill = { rows in
          let database = try launch.database()
          let connection = try database.connect()
          try connection.execute(
            LogPersistence.insertStatement(rows: rows, launchID: launchID, buildVersion: buildVersion)
          )
        }
      } else {
        let database = try LogPersistence.openEphemeral(
          launchID: launchID,
          origin: origin,
          buildVersion: buildVersion,
          startedAtMilliseconds: startedAt
        )
        spill = { rows in
          let connection = try database.connect()
          try connection.execute(
            LogPersistence.insertStatement(rows: rows, launchID: launchID, buildVersion: buildVersion)
          )
          try connection.execute(LogPersistence.trimStatement())
        }
      }
      let writer = LogSpillWriter(
        spill: spill,
        onReport: { Diagnostics.mirrorSpillFailure($0) }
      )
      spillWriter = writer
      store.onMirror = { entry in
        writer.enqueue(
          DiagnosticRow(
            sequence: entry.sequence,
            recordedAtMilliseconds: Int64(entry.capturedAt.timeIntervalSince1970 * 1000),
            level: storedLevel(for: entry.level),
            category: entry.category,
            message: entry.message,
            launchID: launchID,
            buildVersion: buildVersion,
            payloadJSON: entry.payloadJSON
          )
        )
      }
    } catch {
      mirrorSpillFailure("Spill store unavailable: \(error)")
    }
  }

  /// Writes every line still waiting for the spill store, then
  /// closes the store. Called on the way out, since the process may
  /// exit before a scheduled flush runs; a line written afterwards
  /// opens the store again on its own flush.
  static func finishSpilling() {
    spillWriter?.drain()
    launchStore?.close()
  }

  /// The store this launch is writing at `url`, if any. Readers pass
  /// it to `LogQueryExecutor` so the file is never opened twice.
  static func liveSpillStore(at url: URL) -> Database? {
    launchStore?.openDatabase(at: url)
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

  /// The spill path for this launch. Set once ahead of the run
  /// loop; read from emitting threads after that.
  private nonisolated(unsafe) static var spillWriter: LogSpillWriter?
  private nonisolated(unsafe) static var launchStore: LogLaunchStore?

  /// The four stored severity words. Non-standard logger levels
  /// fold into them at record time so level filters never miss.
  private static func storedLevel(for level: Logger.Level) -> String {
    switch level {
    case .trace,
         .debug:
      "debug"
    case .info,
         .notice:
      "info"
    case .warning:
      "warning"
    case .error,
         .critical:
      "error"
    }
  }

}

// MARK: - Logger Metadata grouping

extension Logger.Metadata {
  /// The grouping word the caller attached under the shared key,
  /// if any. Kept out of the emitted line and read by the views.
  var category: String? {
    guard case .string(let word) = self["category"] else {
      return nil
    }
    return word
  }

  /// The attached context as JSON text, keeping nested keys and
  /// arrays. Absent when nothing was attached.
  var payloadJSON: String? {
    guard !isEmpty else {
      return nil
    }
    return "{\(map { "\($0.key.jsonQuoted):\($0.value.jsonText)" }.joined(separator: ","))}"
  }
}

extension Logger.MetadataValue {
  /// Renders one metadata value as JSON text. Convertible values
  /// read through their description, so every shape survives.
  fileprivate var jsonText: String {
    switch self {
    case .string(let text):
      text.jsonQuoted
    case .stringConvertible(let convertible):
      convertible.description.jsonQuoted
    case .array(let values):
      "[\(values.map(\.jsonText).joined(separator: ","))]"
    case .dictionary(let pairs):
      "{\(pairs.lazy.map { "\($0.key.jsonQuoted):\($0.value.jsonText)" }.joined(separator: ","))}"
    }
  }
}

extension String {
  /// Quotes one string for JSON, escaping what JSON forbids raw.
  fileprivate var jsonQuoted: String {
    var out = "\""
    for scalar in unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case Unicode.Scalar(0x08): out += "\\b"
      case Unicode.Scalar(0x0C): out += "\\f"
      default:
        if scalar.value < 0x20 {
          out += String(format: "\\u%04x", scalar.value)
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    out += "\""
    return out
  }
}

// MARK: - DiagnosticLogHandler

/// The one backend this run writes through: stderr and the mirror, as one
/// locked step, so the on-screen log cannot disagree with what was emitted.
/// Takes whatever the logger lets through; the threshold lives on the
/// logger rather than here. A future backend (a file, the system log)
/// arrives as another handler beside this one. Locked around the only
/// mutable state, so sharing it across execution contexts stays sound.
// swiftlint:disable:next no_unchecked_sendable - Every mutable state below is guarded by the lock
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
    store.write(event.message.description, level: event.level, metadata: event.metadata ?? [:])
  }

  // MARK: Private

  private let lock = NSLock()
  private let store: DiagnosticLogStore
  private var metadataStorage: Logger.Metadata = [:]
  private var acceptedLevel = Logger.Level.trace
  private var providerStorage: Logger.MetadataProvider?

}
