import Foundation

// MARK: - Log Window Spill Loading

extension LogWindowState {

  // MARK: Internal

  /// Starts a spill load when the key changed or the cached rows
  /// went stale, and drops the run in flight when a newer key
  /// arrives. The timer heartbeat calls this freely: starting work
  /// never blocks, and only finished results reach the display.
  func ensureSpillLoad(key: String, statement: String?) {
    if key != activeSpillKey {
      startSpillLoad(key: key, statement: statement)
      return
    }
    guard !spillInFlight, !isPaused else { return }
    if
      let finishedAt = lastSpillFinishedAt,
      Date().timeIntervalSince(finishedAt) < Self.spillReloadInterval
    {
      return
    }
    startSpillLoad(key: key, statement: statement)
  }

  /// Takes a finished load from the mailbox onto the display when
  /// it still answers the active key. A newer key means the query
  /// moved on while the load ran, so the stale rows never reach
  /// the sections.
  func takeFinishedSpill() {
    guard let load = spillMailbox.take(generation: spillGeneration, key: activeSpillKey) else {
      return
    }
    spillInFlight = false
    isLoading = false
    lastSpillFinishedAt = Date()
    cachedSpillKey = activeSpillKey
    cachedSpilledRows = load.rows
    cachedSkippedCount = load.skipped
    cachedFailureText = load.failureText
  }

  /// Starts a count-only query when the key changed or the cached
  /// count went stale. Cheap beside the row fetch, so typing
  /// restarts it freely while the display filters cached rows.
  func ensureCountLoad(start: Int64?, end: Int64?) {
    let key = countSpillKey()
    if key != activeCountKey {
      startCountLoad(key: key, start: start, end: end)
      return
    }
    guard !countInFlight, !isPaused else { return }
    if
      let finishedAt = lastCountFinishedAt,
      Date().timeIntervalSince(finishedAt) < Self.spillReloadInterval
    {
      return
    }
    startCountLoad(key: key, start: start, end: end)
  }

  /// Takes a finished count from the mailbox. A newer key means
  /// the row moved on while the count ran, so the stale total
  /// never reaches the status row.
  func takeFinishedCount() {
    guard let total = spillMailbox.takeCount(generation: countGeneration, key: activeCountKey) else {
      return
    }
    countInFlight = false
    lastCountFinishedAt = Date()
    cachedCountKey = activeCountKey
    cachedStoreCount = total
  }

  // MARK: Private

  /// How long a finished spill load stays fresh while the tail runs.
  /// An older result starts a new background load on the next
  /// heartbeat, so rows that aged out of the mirror keep arriving
  /// without blocking the main thread.
  private static let spillReloadInterval: TimeInterval = 2

  /// Lists the spill directory and reads the stores. Runs off the
  /// main thread, so a slow volume never freezes the window.
  /// Cancellation stops between files; unreadable files are skipped
  /// with their count kept, and only a refused statement fails the run.
  nonisolated private static func fetchSpill(statement: String?) -> SpillMailbox.Load {
    let files = spillStoreFiles()
    let executor = LogQueryExecutor(files: files, liveStore: Diagnostics.liveSpillStore(at:))
    do {
      if let statement {
        let result = try executor.runStatement(statement)
        return SpillMailbox.Load(rows: result.rows, skipped: result.skipped.count, failureText: nil)
      }
      let result = try executor.run(predicate: "1 = 1", values: [], limit: 5000)
      return SpillMailbox.Load(rows: result.rows, skipped: result.skipped.count, failureText: nil)
    } catch is CancellationError {
      return SpillMailbox.Load(rows: [], skipped: 0, failureText: nil)
    } catch {
      if statement != nil {
        return SpillMailbox.Load(rows: [], skipped: files.count, failureText: String(describing: error))
      }
      return SpillMailbox.Load(rows: [], skipped: files.count, failureText: nil)
    }
  }

  /// The spill files of this origin, oldest first. Runs off the
  /// main thread from the background fetch, so a slow volume never
  /// freezes scrolling, selection, pause, or editing.
  nonisolated private static func spillStoreFiles() -> [URL] {
    guard
      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else {
      return []
    }
    let origin = LogPersistence.currentOrigin()
    let directory = LogPersistence.directory(applicationSupport: support, origin: origin)
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
      return []
    }
    return names.filter { $0.hasSuffix(".duckdb") }.sorted().map { directory.appendingPathComponent($0) }
  }

  /// Runs one spill load off the main thread. The fetch lists the
  /// directory and reads the stores away from scrolling, selection,
  /// pause, and editing. It stores the finished load in the mailbox;
  /// the heartbeat takes it from there and drops it when a newer
  /// key already replaced it, so the background never touches the
  /// display itself.
  private func startSpillLoad(key: String, statement: String?) {
    spillTask?.cancel()
    spillGeneration += 1
    let generation = spillGeneration
    activeSpillKey = key
    if cachedSpillKey != key {
      cachedSpilledRows = []
      cachedSkippedCount = 0
      cachedFailureText = nil
    }
    spillInFlight = true
    isLoading = true
    spillTask = Task.detached(priority: .utility) { [mailbox = self.spillMailbox, statement, generation, key] in
      let load = Self.fetchSpill(statement: statement)
      guard !Task.isCancelled else { return }
      mailbox.store(load, generation: generation, key: key)
    }
  }

  /// The count key for the lightweight row: the row text plus the
  /// clear marker. The query changes the count; the sliding time
  /// bounds refresh it on the reload interval instead.
  private func countSpillKey() -> String {
    let marker = VersionLogWindow.clearMarkerMilliseconds.map(String.init) ?? "open"
    return "count:" + marker + ":" + query.lightweightText
  }

  /// Counts every store match off the main thread, without any row
  /// cap. The predicate mirrors the display filters: the row text
  /// without the picker-mirrored tokens, plus the toolbar bounds
  /// and the clear marker the display applies around them.
  private func startCountLoad(key: String, start: Int64?, end: Int64?) {
    countTask?.cancel()
    countGeneration += 1
    let generation = countGeneration
    activeCountKey = key
    if cachedCountKey != key {
      cachedStoreCount = nil
    }
    countInFlight = true
    let counted = splitLogQueryTokens(query.lightweightText).filter { !pickerTimeTokens.contains($0) }
      .joined(separator: " ")
    let parsed = LightweightFilter.parse(counted)
    var fragments = [parsed.predicate]
    var values = parsed.values
    if let start {
      fragments.append("ts_ms >= ?")
      values.append(.integer(start))
    }
    if let end {
      fragments.append("ts_ms <= ?")
      values.append(.integer(end))
    }
    if let marker = VersionLogWindow.clearMarkerMilliseconds {
      fragments.append("ts_ms > ?")
      values.append(.integer(marker))
    }
    let predicate = fragments.joined(separator: " AND ")
    countTask = Task.detached(priority: .utility) { [mailbox = self.spillMailbox, predicate, values, generation, key] in
      let total: Int?
      do {
        let files = Self.spillStoreFiles()
        let executor = LogQueryExecutor(files: files, liveStore: Diagnostics.liveSpillStore(at:))
        total = try executor.count(predicate: predicate, values: values)
      } catch {
        total = nil
      }
      guard !Task.isCancelled else { return }
      mailbox.storeCount(total, generation: generation, key: key)
    }
  }

}

// MARK: - SpillMailbox

/// Holds one finished spill load until the heartbeat takes it.
///
/// The background fetch stores here while the main thread takes on
/// its next heartbeat, so a finishing load never touches the display
/// itself and the heartbeat only ever picks up finished results.
/// Every field below crosses the lock, which is why the box carries
/// an unchecked conformance beside this note.
// swiftlint:disable:next no_unchecked_sendable - Every mutable field below is guarded by the lock; stored rows are values
final class SpillMailbox: @unchecked Sendable {

  // MARK: Internal

  /// What one finished background load carries.
  struct Load: Sendable {
    var rows: [DiagnosticRow]
    var skipped: Int
    var failureText: String?
  }

  /// Takes the stored load when it still answers the active key.
  /// Anything older is dropped unread, so a query typed while the
  /// load ran never shows stale rows.
  func take(generation: Int, key: String) -> Load? {
    lock.lock()
    defer { lock.unlock() }
    guard let stored else { return nil }
    self.stored = nil
    guard stored.generation == generation, stored.key == key else {
      return nil
    }
    return stored.load
  }

  /// Stores a finished load for the heartbeat. Overwrites whatever
  /// an older run left, so only the latest result waits.
  func store(_ load: Load, generation: Int, key: String) {
    lock.lock()
    defer { lock.unlock() }
    stored = (load, generation, key)
  }

  /// Takes the stored count when it still answers the active key.
  /// Anything older is dropped unread, so a row typed while the
  /// count ran never shows a stale total.
  func takeCount(generation: Int, key: String) -> Int?? {
    lock.lock()
    defer { lock.unlock() }
    guard let counted else { return nil }
    self.counted = nil
    guard counted.generation == generation, counted.key == key else {
      return nil
    }
    return counted.total
  }

  /// Stores a finished count for the heartbeat. Overwrites whatever
  /// an older run left, so only the latest total waits.
  func storeCount(_ total: Int?, generation: Int, key: String) {
    lock.lock()
    defer { lock.unlock() }
    counted = (total, generation, key)
  }

  // MARK: Private

  private let lock = NSLock()
  private var stored: (load: Load, generation: Int, key: String)?
  private var counted: (total: Int?, generation: Int, key: String)?

}
