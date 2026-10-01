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

  /// The time tokens the picker mirrored into the query row. Only
  /// these stay out of row matching, since the toolbar range already
  /// applies them as bounds; anything hand-typed still filters.
  var pickerTimeTokens = Set<String>()

  var spillTask: Task<Void, Never>?
  var spillInFlight = false
  var spillGeneration = 0
  var activeSpillKey = ""
  var cachedSpillKey: String?
  var cachedSpilledRows = [DiagnosticRow]()
  var cachedSkippedCount = 0
  var cachedFailureText: String?
  var lastSpillFinishedAt: Date?
  let spillMailbox = SpillMailbox()
  var countTask: Task<Void, Never>?
  var countInFlight = false
  var countGeneration = 0
  var activeCountKey = ""
  var cachedCountKey: String?
  var cachedStoreCount: Int?
  var lastCountFinishedAt: Date?

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

  func setSidebarShown(_ shown: Bool) {
    isSidebarShown = shown
    UserDefaults.standard.set(shown, forKey: Self.sidebarKey)
  }

  func setHistogramCollapsed(_ collapsed: Bool) {
    isHistogramCollapsed = collapsed
    UserDefaults.standard.set(collapsed, forKey: Self.histogramKey)
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

  func copy(string: String) {
    guard !string.isEmpty else { return }
    let board = NSPasteboard.general
    board.clearContents()
    board.setString(string, forType: .string)
  }

  func nowMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  // MARK: Private

  /// The spill key while the lightweight row holds the query.
  /// The background fetch reads every store without conditions,
  /// so the key stays put while the text changes and the display
  /// filters the cached rows again on every heartbeat.
  private static let lightweightSpillKey = "lightweight"

  private static let sidebarKey = "LanternaLogSidebarShown"
  private static let histogramKey = "LanternaLogHistogramCollapsed"

  /// The spill key for one database statement: the exact statement
  /// text, so editing the row drops the run in flight.
  private static func databaseSpillKey(for statement: String) -> String {
    "database:" + statement
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
    let activeKey = Diagnostics.activeLaunchID ?? latestKey
    return launchStarts.compactMap { entry in
      guard let rows = byLaunch[entry.key] else { return nil }
      return LogLaunchSection(
        launchID: entry.key == "current" ? nil : entry.key,
        isCurrent: entry.key == activeKey,
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

}
