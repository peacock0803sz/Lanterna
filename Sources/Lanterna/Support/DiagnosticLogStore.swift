import Foundation

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

  /// How many mirrored lines are held, read under the lock without
  /// copying the entries. For counters that need only the count.
  var recentCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return entries.count
  }

  var summary: String? {
    lock.lock()
    defer { lock.unlock() }
    return pinnedSummary
  }

  /// The file this launch's lines are going to, or nil while none is
  /// attached or writing to it has failed.
  var savingTo: URL? {
    lock.lock()
    defer { lock.unlock() }
    guard let writer, !writer.isStopped else { return nil }
    return writer.url
  }

  /// Writes to the real stderr, the message and a newline only.
  static func standardError(_ text: String) {
    try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
  }

  /// The mirrored lines numbered after `sequence`, oldest first. Lets a
  /// reader that polls take only what is new, so the lock the hotkey
  /// paths also take is held for as little copying as possible.
  func entries(after sequence: UInt64) -> [Diagnostics.LogEntry] {
    lock.lock()
    defer { lock.unlock() }
    guard let first = entries.first, sequence >= first.sequence else {
      return entries
    }
    let start = Int(sequence - first.sequence) + 1
    return start < entries.count ? Array(entries[start...]) : []
  }

  /// Emits the line and mirrors it as one locked step. Two calls racing
  /// each other still land in stderr and in the mirror in the same order;
  /// anything weaker would let the on-screen log disagree with what was
  /// emitted. Only the message reaches stderr, so its lines keep the shape
  /// they always had. Tests use `append` directly, which mirrors without
  /// emitting.
  ///
  /// With a writer attached, the line reaches this launch's file in the
  /// same locked step, after stderr and the mirror.
  func write(_ record: Diagnostics.Record) {
    lock.lock()
    defer { lock.unlock() }
    emit(record.message + "\n")
    save(mirror(record))
  }

  /// Starts saving to `writer`'s file. First writes, in order, every
  /// mirrored line not yet written, so the lines from before the file
  /// existed are not lost; done under the lock, so no line slips between
  /// the catching up and the attaching.
  func attach(_ writer: LaunchLogWriter) {
    lock.lock()
    defer { lock.unlock() }
    hasDecided = true
    self.writer = writer
    for entry in entries where entry.sequence > writtenThrough {
      save(entry)
    }
    writtenThrough = nextSequence - 1
  }

  /// Stops saving and closes the file. Lines from now on are counted as
  /// handled, so attaching again later writes only what comes after.
  func detach() {
    lock.lock()
    defer { lock.unlock() }
    writer?.close()
    writer = nil
    hasDecided = true
    writtenThrough = nextSequence - 1
  }

  /// Settles that this launch saves nothing for now, without a writer
  /// ever having been attached.
  func declineSaving() {
    lock.lock()
    defer { lock.unlock() }
    hasDecided = true
    writtenThrough = nextSequence - 1
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
  private var writer: LaunchLogWriter?
  /// The newest line handled for the file: written to it, or passed over
  /// while nothing was attached.
  private var writtenThrough: UInt64 = 0
  /// Whether launch has settled if this run saves. Until it has, lines are
  /// left for the first `attach` to catch up on.
  private var hasDecided = false

  /// Adds one line under the caller's lock.
  @discardableResult
  private func mirror(_ record: Diagnostics.Record) -> Diagnostics.LogEntry {
    let entry = Diagnostics.LogEntry(
      launch: launch,
      sequence: nextSequence,
      capturedAt: Date(),
      level: record.level,
      category: record.category,
      message: record.message,
      source: record.source,
      context: record.context
    )
    entries.append(entry)
    nextSequence += 1
    if entries.count > DiagnosticLog.capacity {
      entries.removeFirst(entries.count - DiagnosticLog.capacity)
    }
    return entry
  }

  /// Writes one line to the file under the caller's lock. A failed write
  /// stops saving for the launch and says so once, on stderr and in the
  /// mirror only; going through the logger would take this lock again.
  private func save(_ entry: Diagnostics.LogEntry) {
    guard hasDecided else { return }
    writtenThrough = entry.sequence
    guard let writer, !writer.isStopped else { return }
    guard !writer.append(LaunchLogCoding.line(for: entry)) else { return }
    let warning = Diagnostics.Record(
      level: .warning,
      category: .logs,
      message: "logs: could not write the saved log; saving stops for this launch: \(writer.url.path)",
      source: DiagnosticLogHandler.source(file: #fileID, line: #line),
      context: ["path": .string(writer.url.path)]
    )
    emit(warning.message + "\n")
    writtenThrough = mirror(warning).sequence
  }

}
