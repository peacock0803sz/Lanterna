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
    timeLabel = TimeRangeResolver.resolve(timeSelection, launchStart: nil).shortLabel
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
      launchStart: nil
    )
    rangeEndMilliseconds = resolved.endMilliseconds
    if resolved.shortLabel != timeLabel {
      timeLabel = resolved.shortLabel
    }
    let start = resolved.startMilliseconds
    let end = resolved.endMilliseconds
    let loaded = loadAll(now: now)
    let afterClear = loaded.filter { row in
      guard let marker = VersionLogWindow.clearMarkerMilliseconds else { return true }
      return row.recordedAtMilliseconds > marker
    }
    if query.mode == .database {
      refreshDatabase(now: now)
      return
    }
    databaseError = nil
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
      matched = timeFiltered.filter { matchesQueryExcludingTime($0, text: text) }
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
    totalCount = afterClear.count
    visibleCount = matched.count
    sections = group(rows: matched)
    launchCount = sections.count
  }

  func togglePause() {
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
    let resolved = TimeRangeResolver.resolve(selection, launchStart: nil)
    timeLabel = resolved.shortLabel
    rewriteTimeTokens(with: resolved.queryTokens)
    refresh()
  }

  func resetTime() {
    timeSelection = TimeRangeSelection()
    let resolved = TimeRangeResolver.resolve(timeSelection, launchStart: nil)
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

  private static let sidebarKey = "LanternaLogSidebarShown"
  private static let histogramKey = "LanternaLogHistogramCollapsed"

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

  private func rewriteTimeTokens(with tokens: [String]) {
    let kept = splitLogQueryTokens(query.lightweightText).filter { entry in
      guard let key = logQueryKey(of: entry)?.lowercased() else { return true }
      return key != "after" && key != "before"
    }
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

  private func loadAll(now: Int64) -> [DiagnosticRow] {
    var merged = [String: DiagnosticRow]()
    let (spilled, skipped) = loadSpilled()
    skippedCount = skipped
    for row in spilled {
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
    if skipped > 0 {
      let top = (rows.map(\.sequence).max() ?? 0) + 1
      rows.append(
        DiagnosticRow(
          sequence: top,
          recordedAtMilliseconds: now,
          level: "warning",
          category: "diagnostics",
          message: "Skipped \(skipped) stored files that could not be read",
          launchID: liveLaunch,
          buildVersion: liveBuild,
          payloadJSON: nil
        )
      )
    }
    return rows.sorted {
      if $0.recordedAtMilliseconds != $1.recordedAtMilliseconds {
        return $0.recordedAtMilliseconds < $1.recordedAtMilliseconds
      }
      return $0.sequence < $1.sequence
    }
  }

  /// Runs the database row text and shows what it returns. A refused
  /// statement shows the refusal instead of rows, using the exact
  /// contract wording, so the row explains why nothing ran. The
  /// statement owns its time bounds, so the toolbar range stays out;
  /// only the clear marker still hides earlier rows. A failed run
  /// shows the failure the same way.
  private func refreshDatabase(now: Int64) {
    let verdict = DatabaseStatementCheck.check(query.databaseText)
    guard verdict.allowed else {
      databaseError = verdict.refusal
      sections = []
      totalCount = 0
      visibleCount = 0
      launchCount = 0
      pendingCount = 0
      afterRangeCount = 0
      return
    }
    let files = spillStoreFiles()
    let executor = LogQueryExecutor(files: files, liveStore: Diagnostics.liveSpillStore(at:))
    do {
      let result = try executor.runStatement(verdict.effectiveText)
      databaseError = nil
      skippedCount = result.skipped.count
      var matched = result.rows
      if let marker = VersionLogWindow.clearMarkerMilliseconds {
        matched = matched.filter { $0.recordedAtMilliseconds > marker }
      }
      if skippedCount > 0 {
        let liveLaunch = Diagnostics.activeLaunchID ?? "current"
        let liveBuild = Diagnostics.activeBuildVersion ?? AppVersion.full
        let top = (matched.map(\.sequence).max() ?? 0) + 1
        matched.append(
          DiagnosticRow(
            sequence: top,
            recordedAtMilliseconds: now,
            level: "warning",
            category: "diagnostics",
            message: "Skipped \(skippedCount) stored files that could not be read",
            launchID: liveLaunch,
            buildVersion: liveBuild,
            payloadJSON: nil
          )
        )
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
    } catch {
      databaseError = String(describing: error)
      sections = []
      totalCount = 0
      visibleCount = 0
      launchCount = 0
      pendingCount = 0
      afterRangeCount = 0
    }
  }

  private func spillStoreFiles() -> [URL] {
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

  private func loadSpilled() -> ([DiagnosticRow], Int) {
    let files = spillStoreFiles()
    guard !files.isEmpty else {
      return ([], 0)
    }
    let executor = LogQueryExecutor(files: files, liveStore: Diagnostics.liveSpillStore(at:))
    do {
      let result = try executor.run(predicate: "1 = 1", values: [], limit: 5000)
      return (result.rows, result.skipped.count)
    } catch {
      return ([], files.count)
    }
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
