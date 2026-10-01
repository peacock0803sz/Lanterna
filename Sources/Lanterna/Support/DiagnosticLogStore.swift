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

  var summary: String? {
    lock.lock()
    defer { lock.unlock() }
    return pinnedSummary
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
