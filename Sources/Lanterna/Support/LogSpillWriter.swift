import Foundation

/// Carries mirrored lines to the spill store on a background queue.
///
/// The panel path never waits on it: callers enqueue under a lock
/// and return, while one scheduled flush after another writes
/// batches. When the buffer overflows or a flush throws, lines are
/// dropped with a count kept, and the failure is reported through
/// the callback instead of the store, so recording the failure can
/// never recurse into the failing writer.
// swiftlint:disable:next no_unchecked_sendable - Every mutable state below is guarded by the lock; the flush lock runs one flush at a time
final class LogSpillWriter: @unchecked Sendable {

  // MARK: Lifecycle

  /// - Parameter spill: writes one batch. Runs off the panel path.
  /// - Parameter onFailure: receives a one-line failure report.
  /// - Parameter bufferCapacity: how many lines wait at most.
  /// - Parameter batchLimit: how many lines one statement carries.
  /// - Parameter schedule: runs a flush later, off the caller's
  ///   thread. Tests pass one that never runs and call `drain`.
  init(
    spill: @escaping ([DiagnosticRow]) throws -> Void,
    onFailure: @escaping (String) -> Void,
    bufferCapacity: Int = 1000,
    batchLimit: Int = 200,
    schedule: @escaping (@escaping () -> Void) -> Void = { LogSpillWriter.background.async(execute: $0) }
  ) {
    self.spill = spill
    self.onFailure = onFailure
    self.bufferCapacity = bufferCapacity
    self.batchLimit = batchLimit
    self.schedule = schedule
  }

  // MARK: Internal

  /// A read of the writer's health.
  struct Snapshot: Equatable, Sendable {
    var buffered: Int
    var droppedTotal: UInt64
    var lastError: String?
  }

  /// Queues one mirrored line for the next flush. Never blocks on
  /// the store: overflow drops the oldest waiting line and counts it.
  func enqueue(_ row: DiagnosticRow) {
    lock.lock()
    buffer.append(row)
    while buffer.count > bufferCapacity {
      buffer.removeFirst()
      droppedTotal += 1
    }
    let scheduled = flushing
    flushing = true
    lock.unlock()
    if !scheduled {
      schedule { [weak self] in self?.flush() }
    }
  }

  /// Reads the writer's health.
  func snapshot() -> Snapshot {
    lock.lock()
    defer { lock.unlock() }
    return Snapshot(buffered: buffer.count, droppedTotal: droppedTotal, lastError: lastError)
  }

  /// Writes every waiting line on the caller's thread before
  /// returning, after any flush already under way.
  func drain() {
    flush()
  }

  // MARK: Private

  private static let background = DispatchQueue(label: "net.p3ac0ck.Lanterna.logSpill", qos: .utility)

  private let lock = NSLock()
  /// Held for a whole flush, so a drain and a scheduled flush never
  /// interleave their batches and lines stay in order.
  private let flushLock = NSLock()
  private let schedule: (@escaping () -> Void) -> Void
  private let spill: ([DiagnosticRow]) throws -> Void
  private let onFailure: (String) -> Void
  private let bufferCapacity: Int
  private let batchLimit: Int
  private var buffer = [DiagnosticRow]()
  private var flushing = false
  private var droppedTotal: UInt64 = 0
  private var lastError: String?

  private func flush() {
    flushLock.lock()
    defer { flushLock.unlock() }
    while true {
      lock.lock()
      guard !buffer.isEmpty else {
        flushing = false
        lock.unlock()
        return
      }
      let batch = Array(buffer.prefix(batchLimit))
      buffer.removeFirst(batch.count)
      lock.unlock()
      do {
        try spill(batch)
      } catch {
        lock.lock()
        droppedTotal += UInt64(batch.count)
        lastError = String(describing: error)
        lock.unlock()
        onFailure("Spilling \(batch.count) lines failed: \(error)")
      }
    }
  }

}
