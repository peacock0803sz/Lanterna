import AppKit
import Foundation
import Logging
import SwiftUI

// MARK: - DisplayedVersion

/// The on-screen version, straight from the generated file.
struct DisplayedVersion: Equatable {
  /// The full describe string, exactly as `Version.swift` holds it.
  let full: String
}

// MARK: - DisplayedLogEntry

/// One log row as the view shows it.
struct DisplayedLogEntry: Identifiable, Equatable {
  /// The store sequence, proving the order.
  let sequence: UInt64
  /// When the line was emitted, for reading only.
  let capturedAt: Date
  /// The line itself.
  let message: String

  var id: UInt64 {
    sequence
  }
}

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
    if query.mode == .lightweight {
      let text = query.lightweightText.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty {
        matched = timeFiltered
      } else {
        matched = timeFiltered.filter { matchesQueryExcludingTime($0, text: text) }
      }
    } else {
      matched = timeFiltered
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

  private func loadSpilled() -> ([DiagnosticRow], Int) {
    guard
      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else {
      return ([], 0)
    }
    let origin = LogPersistence.currentOrigin()
    let directory = LogPersistence.directory(applicationSupport: support, origin: origin)
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
      return ([], 0)
    }
    let files = names.filter { $0.hasSuffix(".duckdb") }.sorted().map { directory.appendingPathComponent($0) }
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

// MARK: - VersionLogWindow

/// The log window.
///
/// Independent from the onboarding window: it opens from the menu-bar entry on
/// any launch, whether or not anything is missing. It reads the store without
/// changing it, and it owns no keyboard monitoring of any kind.
@MainActor
final class VersionLogWindow: NSWindow {

  // MARK: Lifecycle

  /// Shows this launch so far: the version, the pinned summary, then the
  /// mirrored lines in order. A snapshot at opening time; reopening takes a
  /// fresh one.
  convenience init(
    version: DisplayedVersion,
    summary: String?,
    entries _: [DisplayedLogEntry],
    appearanceMode: AppearanceMode = .system
  ) {
    self.init(version: version, summary: summary, appearanceMode: appearanceMode)
  }

  convenience init(
    version: DisplayedVersion,
    summary: String?,
    appearanceMode: AppearanceMode = .system
  ) {
    self.init(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    // Held strongly by GuideWindows; releasing on close would dangle that reference.
    isReleasedWhenClosed = false
    title = "Lanterna Logs"
    appearance = appearanceMode.nsAppearance
    let state = LogWindowState()
    state.refresh()
    contentView = NSHostingView(rootView: LogWindowView(
      version: version,
      summary: summary,
      state: state
    ))
    center()
  }

  // MARK: Internal

  /// Display-only clear point, kept across reopen until relaunch.
  static var clearMarkerMilliseconds: Int64?

}

// MARK: - LogWindowView

/// The log contents with live tail and export.
struct LogWindowView: View {

  // MARK: Internal

  let version: DisplayedVersion
  let summary: String?

  @ObservedObject var state: LogWindowState

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      toolbar
      QueryBarView(
        query: $state.query,
        queryFocused: $queryFocused,
        onCommit: { state.refresh() },
        onModeSwitchRequest: requestModeSwitch,
        timeLabel: state.timeLabel,
        pendingFilteredCount: state.pendingCount,
        isPaused: state.isPaused,
        onRemoveChip: { state.removeChip($0) },
        onClearAll: { state.clearQuery() },
        onResumeFiltered: { state.togglePause() }
      )
      HStack(alignment: .top, spacing: 0) {
        if state.isSidebarShown {
          FieldsSidebar(
            visibleRows: state.flatVisibleRows,
            allRows: state.allKeptRows,
            isEnabled: isLightweight,
            onApply: { state.addQueryToken($0) },
            onExclude: { state.addQueryToken($0) },
            onClose: { state.setSidebarShown(false) }
          )
          Divider()
        }
        VStack(spacing: 0) {
          HistogramView(
            filteredRows: state.flatVisibleRows,
            totalRows: state.allKeptRows,
            launchCount: max(state.allKeptLaunchCount, state.launchCount),
            selectedRowID: state.selection.first,
            isCompact: !state.selection.isEmpty,
            isCollapsed: $state.isHistogramCollapsed,
            isFilteringEnabled: isLightweight,
            onJumpToMilliseconds: { state.jump(toMilliseconds: $0) },
            onShowInterval: { state.showInterval(startMilliseconds: $0, endMilliseconds: $1) },
            onShowLaunch: { state.showLaunch($0) },
            onResetTime: { state.resetTime() },
            onCopyInterval: { state.copyInterval(startMilliseconds: $0, endMilliseconds: $1) },
            onOpenJumpDialog: { },
            oldestKeptDay: state.oldestKeptDay,
            onJumpToDate: { state.jump(to: $0) }
          )
          .onChange(of: state.isHistogramCollapsed) { _, next in
            state.setHistogramCollapsed(next)
          }
          if VersionLogWindow.clearMarkerMilliseconds != nil {
            clearBanner
          }
          if state.afterRangeCount > 0 {
            afterRangeBanner
          }
          if state.flatVisibleRows.isEmpty {
            emptyView
          } else {
            LogTableView(
              sections: state.sections,
              selection: $state.selection,
              autoScroll: state.autoScroll,
              jumpTargetID: state.jumpTargetID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      LogStatusBar(
        visibleCount: state.visibleCount,
        totalCount: state.totalCount,
        launchCount: max(state.allKeptLaunchCount, state.launchCount),
        selectedCount: state.selection.count,
        timeLabel: state.timeLabel,
        isPaused: state.isPaused,
        isFiltered: state.isFiltering,
        autoScroll: $state.autoScroll
      )
    }
    .frame(minWidth: 640, minHeight: 420)
    .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
      state.refresh()
    }
    .background(closeDetailShortcut)
    .alert("Switch query mode?", isPresented: $showSwitchConfirm, presenting: pendingMode) { mode in
      Button("Switch", role: .destructive) {
        state.query.mode = mode
        state.query.lightweightText = ""
        state.query.databaseText = ""
        state.refresh()
        pendingMode = nil
      }
      Button("Cancel", role: .cancel) {
        pendingMode = nil
      }
    } message: { _ in
      Text("The current conditions will be discarded.")
    }
  }

  // MARK: Private

  @FocusState private var queryFocused: Bool
  @State private var showTimePopover = false
  @State private var pendingMode: LogQuery.Mode?
  @State private var showSwitchConfirm = false

  private var isLightweight: Bool {
    state.query.mode == .lightweight
  }

  private var header: some View {
    HStack(spacing: 10) {
      if let icon = NSApp.applicationIconImage {
        Image(nsImage: icon)
          .resizable()
          .frame(width: 32, height: 32)
      }
      VStack(alignment: .leading) {
        Text("Lanterna \(version.full)")
          .font(.headline)
          .textSelection(.enabled)
        if let summary {
          Text(summary)
            .font(.body)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
    }
    .padding(12)
  }

  private var toolbar: some View {
    HStack(spacing: 10) {
      Text(state.liveLabel)
        .font(.subheadline)
        .fontWeight(.medium)
        .accessibilityLabel(state.liveLabel)
      Button {
        state.setSidebarShown(!state.isSidebarShown)
      } label: {
        Image(systemName: "sidebar.left")
      }
      .buttonStyle(.plain)
      .accessibilityLabel(state.isSidebarShown ? "Hide Fields sidebar" : "Show Fields sidebar")
      Menu("Level") {
        Button("All levels") { state.setLevelFilter(nil) }
        Divider()
        Button("Errors only") { state.setLevelFilter("level=error") }
        Button("Warnings and errors") { state.setLevelFilter("level>=warn") }
        Button("Info and above") { state.setLevelFilter("level>=info") }
      }
      .disabled(!isLightweight)
      .accessibilityLabel("Level filter")
      Menu("Category") {
        Button("All categories") { state.setCategoryFilter(nil) }
        Divider()
        ForEach(state.availableCategories, id: \.value) { entry in
          Button("\(entry.value) (\(entry.count))") {
            state.setCategoryFilter("category:\(entry.value)")
          }
        }
      }
      .disabled(!isLightweight)
      .accessibilityLabel("Category filter")
      Menu("Launch") {
        Button("All launches") { state.setLaunchFilter(nil) }
        Divider()
        ForEach(state.availableLaunches, id: \.value) { entry in
          Button(launchMenuTitle(for: entry)) {
            state.setLaunchFilter("launch:\(entry.value)")
          }
        }
      }
      .disabled(!isLightweight)
      .accessibilityLabel("Launch filter")
      Button(state.timeLabel) {
        showTimePopover = true
      }
      .disabled(!isLightweight)
      .accessibilityLabel("Time range \(state.timeLabel)")
      .popover(isPresented: $showTimePopover) {
        TimeRangeView(
          selection: $state.timeSelection,
          launchStart: nil,
          onApply: { selection in
            state.applyTimeSelection(selection)
            showTimePopover = false
          },
          onReset: {
            state.resetTime()
            showTimePopover = false
          }
        )
      }
      Spacer()
      if !state.isDefaultTime {
        Button("Show latest") {
          state.showLatest()
        }
        .accessibilityLabel("Show latest")
      }
      Button(state.isPaused ? "Resume" : "Pause") {
        state.togglePause()
      }
      .keyboardShortcut("p", modifiers: .command)
      .accessibilityLabel(state.isPaused ? "Resume live tail" : "Pause live tail")
      Button("Copy") {
        state.copyText()
      }
      .keyboardShortcut("c", modifiers: .command)
      .accessibilityLabel("Copy selected rows as text")
      Button("Copy JSON") {
        state.copyJSON()
      }
      .keyboardShortcut("c", modifiers: [.command, .option])
      .accessibilityLabel("Copy selected rows as JSON Lines")
      Button("Export") {
        state.exportFile()
      }
      .accessibilityLabel("Export visible rows to a file")
      Button("Clear") {
        state.clearView()
      }
      .accessibilityLabel("Clear visible entries")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }

  private var clearBanner: some View {
    Text("Cleared — earlier entries hidden until relaunch")
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .accessibilityLabel("Cleared, earlier entries hidden until relaunch")
  }

  private var afterRangeBanner: some View {
    HStack {
      Text("\(state.afterRangeCount) new after range · Show latest")
      Button("Show latest") {
        state.showLatest()
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .accessibilityLabel("\(state.afterRangeCount) new after range, show latest")
  }

  private var emptyView: some View {
    VStack(spacing: 8) {
      Spacer()
      if state.totalCount == 0 {
        Text("No log entries yet")
          .font(.body)
          .foregroundStyle(.secondary)
          .accessibilityLabel("No log entries yet")
      } else {
        Text("No entries match the current filters")
          .font(.body)
          .foregroundStyle(.secondary)
          .accessibilityLabel("No entries match the current filters")
        if isLightweight {
          Button("Clear All") {
            state.clearQuery()
          }
          .accessibilityLabel("Clear All filters")
        }
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      state.totalCount == 0 ? "No log entries yet" : "No entries match the current filters"
    )
  }

  private var closeDetailShortcut: some View {
    Button("Close detail") {
      state.selection.removeAll()
    }
    .keyboardShortcut(.cancelAction)
    .hidden()
    .accessibilityLabel("Close detail")
    .accessibilityHint("Clears the row selection and closes the detail")
  }

  private func requestModeSwitch(_ next: LogQuery.Mode) {
    guard next != state.query.mode else { return }
    let current = state.query.activeText.trimmingCharacters(in: .whitespacesAndNewlines)
    if current.isEmpty {
      state.query.mode = next
      state.refresh()
    } else {
      pendingMode = next
      showSwitchConfirm = true
    }
  }

  private func launchMenuTitle(for entry: (value: String, count: Int, isCurrent: Bool)) -> String {
    if entry.isCurrent {
      return "This launch (\(entry.count))"
    }
    let short = entry.value.prefix(8)
    return "\(short) (\(entry.count))"
  }

}

// MARK: - Log Query Matching

/// Splits a query row on whitespace outside quotes, matching the
/// translator so rewrites and display filtering agree.
func splitLogQueryTokens(_ text: String) -> [String] {
  var out = [String]()
  var current = ""
  var quoted = false
  for character in text {
    if character == "\"" {
      quoted.toggle()
      current.append(character)
    } else if character.isWhitespace, !quoted {
      if !current.isEmpty {
        out.append(current)
        current = ""
      }
    } else {
      current.append(character)
    }
  }
  if !current.isEmpty {
    out.append(current)
  }
  return out
}

/// The key before the operator in one token, if the token carries one.
func logQueryKey(of token: String) -> String? {
  let operators = ["!=", ">=", "<=", "=", ">", "<", ":"]
  var index = token.startIndex
  var quoted = false
  while index < token.endIndex {
    let character = token[index]
    if character == "\"" {
      quoted.toggle()
    } else if !quoted {
      for op in operators {
        if token[index...].hasPrefix(op) {
          let key = token[..<index]
          let value = token[token.index(index, offsetBy: op.count)...]
          if !key.isEmpty, !value.isEmpty {
            return String(key)
          }
          return nil
        }
      }
    }
    index = token.index(after: index)
  }
  return nil
}

/// Whether every token besides the time bounds matches the row.
/// Time bounds stay with the toolbar range, so the query text can
/// mirror them for chips without double filtering here.
func matchesQueryExcludingTime(_ row: DiagnosticRow, text: String) -> Bool {
  for token in splitLogQueryTokens(text) {
    if let key = logQueryKey(of: token)?.lowercased(), key == "after" || key == "before" {
      continue
    }
    if !matchesLogQueryToken(row, token: token) {
      return false
    }
  }
  return true
}

private let logLevelOrder = ["debug", "info", "warning", "error"]

private func matchesLogQueryToken(_ row: DiagnosticRow, token: String) -> Bool {
  let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
  guard let split = splitLogQueryOperator(in: token) else {
    return row.message.contains(bare)
  }
  let rawKey = String(split.key)
  let key = rawKey.lowercased()
  let rawValue = String(split.value).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
  switch (key, split.op) {
  case ("level", _):
    return matchesLevel(row.level, op: split.op, word: rawValue.lowercased())
  case ("category", ":"),
       ("category", "="),
       ("category", "!="):
    return matchesOptionalText(row.category, op: split.op, value: rawValue)
  case ("message", ":"),
       ("message", "="),
       ("message", "!="):
    return matchesOptionalText(row.message, op: split.op, value: rawValue)
  case ("launch", ":"),
       ("launch", "="),
       ("launch", "!="):
    return matchesOptionalText(row.launchID, op: split.op, value: rawValue)
  case ("version", ":"),
       ("version", "="),
       ("version", "!="):
    return matchesOptionalText(row.buildVersion, op: split.op, value: rawValue)
  case ("after", ":"):
    return matchesTimeBound(row.recordedAtMilliseconds, bound: rawValue, lower: true)
  case ("before", ":"):
    return matchesTimeBound(row.recordedAtMilliseconds, bound: rawValue, lower: false)
  default:
    guard isValidLogPath(rawKey) else {
      return row.message.contains(bare)
    }
    return matchesPayload(row.payloadJSON, path: rawKey, op: split.op, value: rawValue)
  }
}

private func splitLogQueryOperator(in token: String) -> (key: Substring, op: String, value: Substring)? {
  let operators = ["!=", ">=", "<=", "=", ">", "<", ":"]
  var index = token.startIndex
  var quoted = false
  while index < token.endIndex {
    let character = token[index]
    if character == "\"" {
      quoted.toggle()
    } else if !quoted {
      for op in operators {
        if token[index...].hasPrefix(op) {
          let key = token[..<index]
          let value = token[token.index(index, offsetBy: op.count)...]
          if !key.isEmpty, !value.isEmpty {
            return (key, op, value)
          }
          return nil
        }
      }
    }
    index = token.index(after: index)
  }
  return nil
}

private func isValidLogPath(_ key: String) -> Bool {
  guard !key.isEmpty, key.count <= 128 else { return false }
  let segments = key.split(separator: ".", omittingEmptySubsequences: false)
  for segment in segments {
    var name = segment
    if name.hasSuffix("[]") {
      name = name.dropLast(2)
    }
    guard !name.isEmpty, name.count <= 64 else { return false }
    guard let first = name.first, first.isLetter || first == "_" else { return false }
    guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return false }
  }
  return true
}

private func matchesLevel(_ level: String, op: String, word: String) -> Bool {
  let canonical = word == "warn" ? "warning" : word
  guard let rank = logLevelOrder.firstIndex(of: canonical) else { return false }
  let current = level.lowercased()
  switch op {
  case ">=":
    guard let currentRank = logLevelOrder.firstIndex(of: current) else { return false }
    return currentRank >= rank

  case ">":
    guard let currentRank = logLevelOrder.firstIndex(of: current) else { return false }
    return currentRank > rank

  case "<=":
    guard let currentRank = logLevelOrder.firstIndex(of: current) else { return false }
    return currentRank <= rank

  case "<":
    guard let currentRank = logLevelOrder.firstIndex(of: current) else { return false }
    return currentRank < rank

  case "!=":
    return current != canonical

  default:
    return current == canonical
  }
}

private func matchesOptionalText(_ field: String?, op: String, value: String) -> Bool {
  switch op {
  case "=":
    return field == value
  case "!=":
    return field == nil || field != value
  default:
    guard let field else { return false }
    return field.contains(value)
  }
}

private func matchesTimeBound(_ milliseconds: Int64, bound: String, lower: Bool) -> Bool {
  guard let limit = logBoundMilliseconds(bound) else { return false }
  return lower ? milliseconds >= limit : milliseconds <= limit
}

private func logBoundMilliseconds(_ bound: String) -> Int64? {
  let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"]
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone.current
  for format in formats {
    formatter.dateFormat = format
    if let date = formatter.date(from: bound) {
      return Int64(date.timeIntervalSince1970 * 1000)
    }
  }
  return nil
}

private func matchesPayload(_ text: String?, path: String, op: String, value: String) -> Bool {
  let values = payloadStrings(text, path: path)
  switch op {
  case "=":
    return values.contains(value)

  case "!=":
    if values.isEmpty {
      return true
    }
    return !values.contains(value)

  default:
    return values.contains { $0.contains(value) }
  }
}

private func payloadStrings(_ text: String?, path: String) -> [String] {
  guard
    let text, let data = text.data(using: .utf8),
    let root = try? JSONSerialization.jsonObject(with: data)
  else { return [] }
  var current: [Any] = [root]
  let segments = path.split(separator: ".").map(String.init)
  for segment in segments {
    var next = [Any]()
    if segment.hasSuffix("[]") {
      let name = String(segment.dropLast(2))
      for item in current {
        guard let dict = item as? [String: Any], let array = dict[name] as? [Any] else { continue }
        next.append(contentsOf: array)
      }
    } else {
      for item in current {
        if let dict = item as? [String: Any], let found = dict[segment] {
          next.append(found)
        } else if let array = item as? [Any] {
          for element in array {
            if let dict = element as? [String: Any], let found = dict[segment] {
              next.append(found)
            }
          }
        }
      }
    }
    current = next
  }
  return current.compactMap { value in
    if let text = value as? String {
      return text
    }
    if let number = value as? NSNumber {
      return number.stringValue
    }
    return nil
  }
}
