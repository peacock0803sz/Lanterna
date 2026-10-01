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
  /// which mirrors without writing to stderr.
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
  /// alongside in the mirror and the spill store fed from it.
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
  /// extra fields ride beside the line in the mirror and the spill
  /// store. They never reach stderr, so the emitted lines keep the
  /// shape existing readers of stderr rely on.
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

  /// The launch this process spills as, when spilling started.
  nonisolated(unsafe) static var activeLaunchID: String?
  /// The build this process spills as, when spilling started.
  nonisolated(unsafe) static var activeBuildVersion: String?
  /// When this launch started, as milliseconds since the epoch.
  /// Read by the log window so the Since-this-launch range starts
  /// at this launch instead of showing everything kept.
  nonisolated(unsafe) static var activeLaunchStartMilliseconds: Int64?

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
    // Record everything; filtering happens through window queries alone.
    logger.logLevel = .trace
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
    activeLaunchID = launchID
    activeBuildVersion = buildVersion
    spillPersists = persist
    let origin = LogPersistence.currentOrigin()
    let startedAt = Int64(Foundation.Date().timeIntervalSince1970 * 1000)
    activeLaunchStartMilliseconds = startedAt
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

  /// Follows a settings change for the rest of the run. A new
  /// rotation applies to later writes without disturbing the open
  /// store; switching persistence drains the old path and starts the
  /// new one under the same launch identity.
  static func updateSpilling(persist: Bool, rotation: LogRotation) {
    if persist == spillPersists {
      launchStore?.update(rotation: rotation)
      return
    }
    guard let launchID = activeLaunchID, let buildVersion = activeBuildVersion else { return }
    guard
      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else {
      return
    }
    spillWriter?.drain()
    store.onMirror = nil
    launchStore?.close()
    launchStore = nil
    spillWriter = nil
    startSpilling(
      applicationSupport: support,
      launchID: launchID,
      buildVersion: buildVersion,
      rotation: rotation,
      persist: persist
    )
  }

  /// Trims one origin down to the retention window and the disk cap,
  /// sparing the running launch. Caps read as decimal gigabytes, the
  /// way the settings display them.
  static func enforceSpillRetention(retentionDays: Int, diskLimitGB: Int) {
    guard
      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else {
      return
    }
    let origin = LogPersistence.currentOrigin()
    let directory = LogPersistence.directory(applicationSupport: support, origin: origin)
    let keeping = activeLaunchID.map { Set([$0]) } ?? []
    let removed = LogPersistence.enforceRetention(
      in: directory,
      retentionDays: retentionDays,
      diskLimitBytes: Int64(diskLimitGB) * 1_000_000_000,
      keepingLaunchIDs: keeping
    )
    if removed > 0 {
      writeLine("trimmed \(removed) spill files past retention", level: .info)
    }
  }

  /// Closes the live spill store ahead of removing its files. The
  /// writer keeps its place: the next spill opens a fresh store on
  /// demand, so closing never loses a line. Called around deleting
  /// saved logs, where the open handle would otherwise keep writing
  /// to an unlinked file after its directory entry is gone.
  static func closeLiveSpillStore() {
    launchStore?.close()
  }

  /// Opens the live spill store anew after its files were removed.
  /// Later spills land in a fresh file rather than an unlinked
  /// handle left behind by the removal.
  static func reopenLiveSpillStore() {
    guard let launch = launchStore else {
      return
    }
    do {
      _ = try launch.database()
    } catch {
      mirrorSpillFailure("Spill store unavailable: \(error)")
    }
  }

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

  /// The spill path for this launch: the writer and, when the launch
  /// persists, the store behind it. Set once ahead of the run loop;
  /// read after that only to drain, look up, and close them.
  private nonisolated(unsafe) static var spillWriter: LogSpillWriter?
  private nonisolated(unsafe) static var launchStore: LogLaunchStore?
  /// Whether the running spill path persists to disk. Follows the
  /// settings through `updateSpilling`; read only to tell a rotation
  /// change apart from a persistence switch.
  private nonisolated(unsafe) static var spillPersists = true

  /// The stored severity words. Logger levels without a word of
  /// their own, trace, notice, and critical, fold into the nearest
  /// one at record time so level filters never miss.
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
