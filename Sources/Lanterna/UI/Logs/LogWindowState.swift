import AppKit
import Foundation
import Logging
import SwiftUI

// MARK: - LogWindowState

/// Live contents behind the log window.
///
/// Reads the in-memory mirror plus the same-origin spilled files,
/// groups by launch, and applies the display-only filters. Pausing
/// freezes the shown list while counting what arrived meanwhile.
/// The lightweight query string stays the single place that holds
/// the level, category, launch, and payload conditions, so every
/// toolbar menu, sidebar pick, and histogram action rewrites that
/// string instead of keeping a second filter beside it.
@MainActor
final class LogWindowState: ObservableObject {

  // MARK: Lifecycle

  init() {
    isSidebarShown = UserDefaults.standard.bool(forKey: Self.sidebarKey)
    isHistogramCollapsed = UserDefaults.standard.bool(forKey: Self.histogramKey)
    timeLabel = TimeRangeResolver.resolve(timeSelection, launchStart: launchStart).shortLabel
  }

  // MARK: Internal

  @Published var sections = [LogLaunchSection]()
  @Published var selection = Set<String>()
  @Published var isPaused = false
  @Published var pendingCount = 0
  @Published var autoScroll = true
  @Published var totalCount = 0
  @Published var visibleCount = 0
  @Published var launchCount = 0
  @Published var timeLabel = "Last 1 hour"
  @Published var rangeEndMilliseconds: Int64?
  @Published var afterRangeCount = 0
  @Published var skippedCount = 0
  @Published var query = LogQuery.fresh
  @Published var timeSelection = TimeRangeSelection()
  @Published var isSidebarShown = false
  @Published var isHistogramCollapsed = false
  @Published var allKeptRows = [DiagnosticRow]()
  @Published var jumpTargetID: String?
  @Published var databaseError: String?
  @Published var isLoading = false

  var liveLabel: String {
    if let end = rangeEndMilliseconds, end < nowMilliseconds() {
      return "Not live · range ends \(LogExport.fullTime(milliseconds: end).prefix(19))"
    }
    if isPaused {
      if pendingCount > 0 {
        return "Paused · \(pendingCount) new entries waiting"
      }
      return "Paused"
    }
    return "Live · level \(effectiveLevelName) and above"
  }

  /// Where the Live level comes from. The threshold is fixed at
  /// launch from the config file or the launch argument, so the
  /// window only points at the place to change it.
  var levelHint: String {
    "Set with logLevel in the config file or --log-level; takes effect on next launch."
  }

  var flatVisibleRows: [DiagnosticRow] {
    sections.flatMap(\.rows)
  }

  var isFiltering: Bool {
    guard query.mode == .lightweight else { return false }
    return !query.lightweightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var isDefaultTime: Bool {
    timeSelection == TimeRangeSelection()
  }

  var allKeptLaunchCount: Int {
    Set(allKeptRows.map { $0.launchID ?? "current" }).count
  }

  var oldestKeptDay: Date {
    guard let earliest = allKeptRows.map(\.recordedAtMilliseconds).min() else { return Date() }
    return Date(timeIntervalSince1970: Double(earliest) / 1_000)
  }

  var availableCategories: [(value: String, count: Int)] {
    var tallies = [String: Int]()
    for row in allKeptRows {
      guard let category = row.category else { continue }
      tallies[category, default: 0] += 1
    }
    return tallies.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
  }

  var availableLaunches: [(value: String, count: Int, isCurrent: Bool)] {
    let current = Diagnostics.activeLaunchID
    var tallies = [String: Int]()
    for row in allKeptRows {
      tallies[row.launchID ?? "current", default: 0] += 1
    }
    return tallies.sorted { $0.key < $1.key }.map { entry in
      (entry.key, entry.value, current.map { $0 == entry.key } ?? (entry.key == "current"))
    }
  }

  func refresh() {
    let now = nowMilliseconds()
    let resolved = TimeRangeResolver.resolve(
      timeSelection,
      now: Date(timeIntervalSince1970: Double(now) / 1_000),
      launchStart: launchStart
    )
    rangeEndMilliseconds = resolved.endMilliseconds
    if resolved.shortLabel != timeLabel {
      timeLabel = resolved.shortLabel
    }
    let start = resolved.startMilliseconds
    let end = resolved.endMilliseconds
    takeFinishedSpill()
    if query.mode == .database {
      refreshDatabase(now: now)
      return
    }
    databaseError = nil
    takeFinishedCount()
    ensureSpillLoad(key: Self.lightweightSpillKey, statement: nil)
    ensureCountLoad(start: start, end: end)
    updateLightweightDisplay(now: now, start: start, end: end)
  }

  func togglePause() {
    lastSpillFinishedAt = nil
    lastCountFinishedAt = nil
    if isPaused {
      isPaused = false
      refresh()
    } else {
      isPaused = true
      refresh()
    }
  }

  func clearView() {
    VersionLogWindow.clearMarkerMilliseconds = nowMilliseconds()
    isPaused = false
    pendingCount = 0
    refresh()
  }

  func showLatest() {
    resetTime()
    isPaused = false
    pendingCount = 0
  }

  func setSidebarShown(_ shown: Bool) {
    isSidebarShown = shown
    UserDefaults.standard.set(shown, forKey: Self.sidebarKey)
  }

  func setHistogramCollapsed(_ collapsed: Bool) {
    isHistogramCollapsed = collapsed
    UserDefaults.standard.set(collapsed, forKey: Self.histogramKey)
  }

  func addQueryToken(_ token: String) {
    guard query.mode == .lightweight else { return }
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var tokens = splitLogQueryTokens(query.lightweightText)
    if tokens.contains(trimmed) {
      return
    }
    tokens.append(trimmed)
    query.lightweightText = tokens.joined(separator: " ")
    refresh()
  }

  func replaceQueryKeys(_ keys: [String], with token: String?) {
    guard query.mode == .lightweight else { return }
    let lowered = Set(keys.map { $0.lowercased() })
    var tokens = splitLogQueryTokens(query.lightweightText).filter { entry in
      guard let key = logQueryKey(of: entry)?.lowercased() else { return true }
      return !lowered.contains(key)
    }
    if let token {
      let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        tokens.append(trimmed)
      }
    }
    query.lightweightText = tokens.joined(separator: " ")
    refresh()
  }

  func setLevelFilter(_ token: String?) {
    replaceQueryKeys(["level"], with: token)
  }

  func setCategoryFilter(_ token: String?) {
    replaceQueryKeys(["category", "cat"], with: token)
  }

  func setLaunchFilter(_ token: String?) {
    replaceQueryKeys(["launch"], with: token)
  }

  func removeChip(_ chip: String) {
    guard query.mode == .lightweight else { return }
    if chip == "__time__" {
      resetTime()
      return
    }
    let parsed = LightweightFilter.parse(query.lightweightText)
    query.lightweightText = parsed.removingChip(chip)
    refresh()
  }

  func clearQuery() {
    guard query.mode == .lightweight else { return }
    query.lightweightText = ""
    resetTime()
  }

  func applyTimeSelection(_ selection: TimeRangeSelection) {
    guard query.mode == .lightweight else {
      timeSelection = selection
      refresh()
      return
    }
    timeSelection = selection
    let resolved = TimeRangeResolver.resolve(selection, launchStart: launchStart)
    timeLabel = resolved.shortLabel
    rewriteTimeTokens(with: resolved.queryTokens)
    refresh()
  }

  func resetTime() {
    timeSelection = TimeRangeSelection()
    pickerTimeTokens = []
    let resolved = TimeRangeResolver.resolve(timeSelection, launchStart: launchStart)
    timeLabel = resolved.shortLabel
    if query.mode == .lightweight {
      let kept = splitLogQueryTokens(query.lightweightText).filter { entry in
        guard let key = logQueryKey(of: entry)?.lowercased() else { return true }
        return key != "after" && key != "before"
      }
      query.lightweightText = kept.joined(separator: " ")
    }
    refresh()
  }

  func showInterval(startMilliseconds start: Int64, endMilliseconds end: Int64) {
    guard query.mode == .lightweight else { return }
    var selection = TimeRangeSelection()
    selection.kind = .custom
    selection.customStart = Date(timeIntervalSince1970: Double(start) / 1_000)
    selection.customEnd = Date(timeIntervalSince1970: Double(end) / 1_000)
    applyTimeSelection(selection)
  }

  func showLaunch(_ launchID: String) {
    guard query.mode == .lightweight else { return }
    replaceQueryKeys(["launch"], with: "launch:\(launchID)")
  }

  func jump(toMilliseconds milliseconds: Int64) {
    let scope = flatVisibleRows.isEmpty ? allKeptRows : flatVisibleRows
    guard
      let near = scope.min(by: {
        abs($0.recordedAtMilliseconds - milliseconds) < abs($1.recordedAtMilliseconds - milliseconds)
      })
    else { return }
    selection = [near.rowID]
    jumpTargetID = near.rowID
  }

  func jump(to date: Date) {
    jump(toMilliseconds: Int64(date.timeIntervalSince1970 * 1_000))
  }

  func copyInterval(startMilliseconds start: Int64, endMilliseconds end: Int64) {
    let rows = flatVisibleRows.filter { row in
      row.recordedAtMilliseconds >= start && row.recordedAtMilliseconds < end
    }
    copy(string: LogExport.textLines(rows: rows))
  }

  func targetRows() -> [DiagnosticRow] {
    let visible = flatVisibleRows
    guard !selection.isEmpty else { return visible }
    let wanted = selection
    return visible.filter { wanted.contains($0.rowID) }
  }

  func copyText() {
    copy(string: LogExport.textLines(rows: targetRows()))
  }

  func copyJSON() {
    copy(string: LogExport.jsonLines(rows: targetRows()))
  }

  func exportFile() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Lanterna Logs.jsonl"
    panel.allowsOtherFileTypes = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let body = LogExport.fileContents(rows: flatVisibleRows)
    try? body.write(to: url, atomically: true, encoding: .utf8)
  }

  // MARK: Private

  /// The spill key while the lightweight row holds the query.
  /// The background fetch reads every store without conditions,
  /// so the key stays put while the text changes and the display
  /// filters the cached rows again on every heartbeat.
  private static let lightweightSpillKey = "lightweight"

  /// How long a finished spill load stays fresh while the tail runs.
  /// An older result starts a new background load on the next
  /// heartbeat, so rows that aged out of the mirror keep arriving
  /// without blocking the main thread.
  private static let spillReloadInterval: TimeInterval = 2

  private static let sidebarKey = "LanternaLogSidebarShown"
  private static let histogramKey = "LanternaLogHistogramCollapsed"

  private var spillTask: Task<Void, Never>?
  private var spillInFlight = false
  private var spillGeneration = 0
  private var activeSpillKey = ""
  private var cachedSpillKey: String?
  private var cachedSpilledRows = [DiagnosticRow]()
  private var cachedSkippedCount = 0
  private var cachedFailureText: String?
  private var lastSpillFinishedAt: Date?
  private let spillMailbox = SpillMailbox()
  private var countTask: Task<Void, Never>?
  private var countInFlight = false
  private var countGeneration = 0
  private var activeCountKey = ""
  private var cachedCountKey: String?
  private var cachedStoreCount: Int?
  private var lastCountFinishedAt: Date?
  /// The time tokens the picker mirrored into the query row. Only
  /// these stay out of row matching, since the toolbar range already
  /// applies them as bounds; anything hand-typed still filters.
  private var pickerTimeTokens = Set<String>()

  private var effectiveLevelName: String {
    guard let logger = Diagnostics.logger else { return "Warning" }
    return switch logger.logLevel {
    case .trace: "Trace"
    case .debug: "Debug"
    case .info: "Info"
    case .notice: "Notice"
    case .warning: "Warning"
    case .error: "Error"
    case .critical: "Critical"
    }
  }

  /// When this launch started, for the Since-this-launch range.
  /// Absent before the first spill, where the range stays open
  /// and shows everything kept.
  private var launchStart: Date? {
    Diagnostics.activeLaunchStartMilliseconds.map { Date(timeIntervalSince1970: Double($0) / 1_000) }
  }

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

  /// The spill key for one database statement: the exact statement
  /// text, so editing the row drops the run in flight.
  private static func databaseSpillKey(for statement: String) -> String {
    "database:" + statement
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

  /// Starts a spill load when the key changed or the cached rows
  /// went stale, and drops the run in flight when a newer key
  /// arrives. The timer heartbeat calls this freely: starting work
  /// never blocks, and only finished results reach the display.
  private func ensureSpillLoad(key: String, statement: String?) {
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

  /// Takes a finished load from the mailbox onto the display when
  /// it still answers the active key. A newer key means the query
  /// moved on while the load ran, so the stale rows never reach
  /// the sections.
  private func takeFinishedSpill() {
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

  /// Merges the cached spill rows with the live mirror and applies
  /// the display-only filters. Cheap enough for the heartbeat: the
  /// listing and the store reads already happened in the background.
  private func updateLightweightDisplay(now: Int64, start: Int64?, end: Int64?) {
    let afterClear = mergedKeptRows(now: now)
    allKeptRows = afterClear
    let timeFiltered = afterClear.filter { row in
      if let start, row.recordedAtMilliseconds < start {
        return false
      }
      if let end, row.recordedAtMilliseconds > end {
        return false
      }
      return true
    }
    let matched: [DiagnosticRow]
    let text = query.lightweightText.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
      matched = timeFiltered
    } else {
      matched = timeFiltered.filter { matchesQuery($0, text: text, excluding: pickerTimeTokens) }
    }
    let afterRange: [DiagnosticRow] =
      if let end {
        afterClear.filter { $0.recordedAtMilliseconds > end }
      } else {
        []
      }
    if isPaused, !sections.isEmpty {
      let shownIDs = Set(flatVisibleRows.map(\.rowID))
      let freshIDs = Set(matched.map(\.rowID))
      pendingCount = freshIDs.subtracting(shownIDs).count
      afterRangeCount = afterRange.count
      return
    }
    pendingCount = 0
    afterRangeCount = afterRange.count
    totalCount = fullMatchCount(matched: matched, start: start, end: end, text: text)
    visibleCount = matched.count
    sections = group(rows: matched)
    launchCount = sections.count
  }

  /// The count key for the lightweight row: the row text plus the
  /// clear marker. The query changes the count; the sliding time
  /// bounds refresh it on the reload interval instead.
  private func countSpillKey() -> String {
    let marker = VersionLogWindow.clearMarkerMilliseconds.map(String.init) ?? "open"
    return "count:" + marker + ":" + query.lightweightText
  }

  /// Starts a count-only query when the key changed or the cached
  /// count went stale. Cheap beside the row fetch, so typing
  /// restarts it freely while the display filters cached rows.
  private func ensureCountLoad(start: Int64?, end: Int64?) {
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

  /// Takes a finished count from the mailbox. A newer key means
  /// the row moved on while the count ran, so the stale total
  /// never reaches the status row.
  private func takeFinishedCount() {
    guard let total = spillMailbox.takeCount(generation: countGeneration, key: activeCountKey) else {
      return
    }
    countInFlight = false
    lastCountFinishedAt = Date()
    cachedCountKey = activeCountKey
    cachedStoreCount = total
  }

  /// The full match count for the status total: the shown matches
  /// plus the store matches outside the capped window, from the
  /// count-only query. Falls back to the kept rows while the count
  /// is still loading, so the total never blinks empty.
  private func fullMatchCount(matched: [DiagnosticRow], start: Int64?, end: Int64?, text: String) -> Int {
    guard let storeTotal = cachedStoreCount, cachedCountKey == activeCountKey else {
      return allKeptRows.count
    }
    let marker = VersionLogWindow.clearMarkerMilliseconds
    let windowMatches = cachedSpilledRows.count(where: { row in
      if let marker, row.recordedAtMilliseconds <= marker {
        return false
      }
      if let start, row.recordedAtMilliseconds < start {
        return false
      }
      if let end, row.recordedAtMilliseconds > end {
        return false
      }
      if text.isEmpty {
        return true
      }
      return matchesQuery(row, text: text, excluding: pickerTimeTokens)
    })
    return matched.count + max(0, storeTotal - windowMatches)
  }

  private func rewriteTimeTokens(with tokens: [String]) {
    let kept = splitLogQueryTokens(query.lightweightText).filter { entry in
      guard let key = logQueryKey(of: entry)?.lowercased() else { return true }
      return key != "after" && key != "before"
    }
    pickerTimeTokens = Set(tokens)
    query.lightweightText = (kept + tokens).joined(separator: " ")
  }

  private func nowMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  private func group(rows: [DiagnosticRow]) -> [LogLaunchSection] {
    let ordered = rows.sorted {
      if $0.recordedAtMilliseconds != $1.recordedAtMilliseconds {
        return $0.recordedAtMilliseconds < $1.recordedAtMilliseconds
      }
      return $0.sequence < $1.sequence
    }
    var byLaunch = [String: [DiagnosticRow]]()
    var order = [String]()
    for row in ordered {
      let key = row.launchID ?? "current"
      if byLaunch[key] == nil {
        order.append(key)
        byLaunch[key] = []
      }
      byLaunch[key]?.append(row)
    }
    var launchStarts = [(key: String, start: Int64)]()
    for key in order {
      let start = byLaunch[key]?.map(\.recordedAtMilliseconds).min() ?? 0
      launchStarts.append((key, start))
    }
    launchStarts.sort { $0.start < $1.start }
    let latestKey = launchStarts.last?.key
    return launchStarts.compactMap { entry in
      guard let rows = byLaunch[entry.key] else { return nil }
      return LogLaunchSection(
        launchID: entry.key == "current" ? nil : entry.key,
        isCurrent: entry.key == latestKey,
        startMilliseconds: entry.start,
        rows: rows
      )
    }
  }

  /// Merges the cached spill rows with the live mirror, the mirror
  /// winning on a shared key. The clear marker hides earlier rows
  /// here, so every display path honors one clearing.
  private func mergedKeptRows(now: Int64) -> [DiagnosticRow] {
    var merged = [String: DiagnosticRow]()
    for row in cachedSpilledRows {
      merged["\(row.launchID ?? "spilled")-\(row.sequence)"] = row
    }
    let liveLaunch = Diagnostics.activeLaunchID ?? "current"
    let liveBuild = Diagnostics.activeBuildVersion ?? AppVersion.full
    for entry in Diagnostics.recentEntries {
      let row = DiagnosticRow(
        sequence: entry.sequence,
        recordedAtMilliseconds: Int64(entry.capturedAt.timeIntervalSince1970 * 1000),
        level: storedWord(for: entry.level),
        category: entry.category,
        message: entry.message,
        launchID: liveLaunch,
        buildVersion: liveBuild,
        payloadJSON: entry.payloadJSON
      )
      merged["\(liveLaunch)-\(entry.sequence)"] = row
    }
    var rows = Array(merged.values)
    skippedCount = cachedSkippedCount
    if skippedCount > 0 {
      rows.append(spillWarningRow(beside: rows, now: now))
    }
    let kept = rows.sorted {
      if $0.recordedAtMilliseconds != $1.recordedAtMilliseconds {
        return $0.recordedAtMilliseconds < $1.recordedAtMilliseconds
      }
      return $0.sequence < $1.sequence
    }
    guard let marker = VersionLogWindow.clearMarkerMilliseconds else {
      return kept
    }
    return kept.filter { $0.recordedAtMilliseconds > marker }
  }

  /// One warning row standing in for the spill files left unread.
  /// Kept beside the rows shown, so the count of skipped files
  /// never silently vanishes from the display.
  private func spillWarningRow(beside rows: [DiagnosticRow], now: Int64) -> DiagnosticRow {
    let liveLaunch = Diagnostics.activeLaunchID ?? "current"
    let liveBuild = Diagnostics.activeBuildVersion ?? AppVersion.full
    let top = (rows.map(\.sequence).max() ?? 0) + 1
    return DiagnosticRow(
      sequence: top,
      recordedAtMilliseconds: now,
      level: "warning",
      category: "diagnostics",
      message: "Skipped \(cachedSkippedCount) stored files that could not be read",
      launchID: liveLaunch,
      buildVersion: liveBuild,
      payloadJSON: nil
    )
  }

  /// Shows what the database row text returns. A refused statement
  /// shows the refusal at once with no store read, using the exact
  /// contract wording, so the row explains why nothing ran. An
  /// allowed statement reads in the background like the lightweight
  /// fetch; the heartbeat shows the finished rows. The statement
  /// owns its time bounds, so the toolbar range stays out; only the
  /// clear marker still hides earlier rows.
  private func refreshDatabase(now: Int64) {
    countTask?.cancel()
    countTask = nil
    countInFlight = false
    let verdict = DatabaseStatementCheck.check(query.databaseText)
    guard verdict.allowed else {
      spillTask?.cancel()
      spillTask = nil
      spillInFlight = false
      isLoading = false
      activeSpillKey = Self.databaseSpillKey(for: query.databaseText)
      databaseError = verdict.refusal
      sections = []
      totalCount = 0
      visibleCount = 0
      launchCount = 0
      pendingCount = 0
      afterRangeCount = 0
      return
    }
    let key = Self.databaseSpillKey(for: verdict.effectiveText)
    ensureSpillLoad(key: key, statement: verdict.effectiveText)
    updateDatabaseDisplay(now: now, key: key)
  }

  /// Shows the finished statement rows when they answer the active
  /// statement. Rows from an older statement stay out while the new
  /// run is in flight, with the progress mark holding their place.
  private func updateDatabaseDisplay(now: Int64, key: String) {
    guard cachedSpillKey == key else {
      sections = []
      totalCount = 0
      visibleCount = 0
      launchCount = 0
      pendingCount = 0
      afterRangeCount = 0
      return
    }
    if let failure = cachedFailureText {
      databaseError = failure
      sections = []
      totalCount = 0
      visibleCount = 0
      launchCount = 0
      pendingCount = 0
      afterRangeCount = 0
      return
    }
    databaseError = nil
    skippedCount = cachedSkippedCount
    var matched = cachedSpilledRows
    if let marker = VersionLogWindow.clearMarkerMilliseconds {
      matched = matched.filter { $0.recordedAtMilliseconds > marker }
    }
    if skippedCount > 0 {
      matched.append(spillWarningRow(beside: matched, now: now))
    }
    allKeptRows = matched
    if isPaused, !sections.isEmpty {
      let shownIDs = Set(flatVisibleRows.map(\.rowID))
      let freshIDs = Set(matched.map(\.rowID))
      pendingCount = freshIDs.subtracting(shownIDs).count
      afterRangeCount = 0
      return
    }
    pendingCount = 0
    afterRangeCount = 0
    totalCount = matched.count
    visibleCount = matched.count
    sections = group(rows: matched)
    launchCount = sections.count
  }

  private func storedWord(for level: Logger.Level) -> String {
    switch level {
    case .trace,
         .debug: "debug"
    case .info,
         .notice: "info"
    case .warning: "warning"
    case .error,
         .critical: "error"
    }
  }

  private func copy(string: String) {
    guard !string.isEmpty else { return }
    let board = NSPasteboard.general
    board.clearContents()
    board.setString(string, forType: .string)
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
