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
@MainActor
final class LogWindowState: ObservableObject {

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

  func refresh() {
    let now = nowMilliseconds()
    let end = rangeEndMilliseconds ?? now
    let start = end - Self.windowMilliseconds
    let loaded = loadAll(now: now)
    let afterClear = loaded.filter { row in
      guard let marker = VersionLogWindow.clearMarkerMilliseconds else { return true }
      return row.recordedAtMilliseconds > marker
    }
    let visible = afterClear.filter { $0.recordedAtMilliseconds >= start && $0.recordedAtMilliseconds <= end }
    let afterRange = afterClear.filter { $0.recordedAtMilliseconds > end }
    if isPaused, !sections.isEmpty {
      let shownIDs = Set(flatVisibleRows.map(\.rowID))
      let freshIDs = Set(visible.map(\.rowID))
      pendingCount = freshIDs.subtracting(shownIDs).count
      afterRangeCount = afterRange.count
      return
    }
    pendingCount = 0
    afterRangeCount = afterRange.count
    totalCount = afterClear.count
    visibleCount = visible.count
    sections = group(rows: visible)
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
    rangeEndMilliseconds = nil
    timeLabel = "Last 1 hour"
    isPaused = false
    pendingCount = 0
    refresh()
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

  private static let windowMilliseconds: Int64 = 3_600_000

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
      if VersionLogWindow.clearMarkerMilliseconds != nil {
        clearBanner
      }
      if state.afterRangeCount > 0 {
        afterRangeBanner
      }
      LogTableView(sections: state.sections, selection: $state.selection, autoScroll: state.autoScroll)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      LogStatusBar(
        visibleCount: state.visibleCount,
        totalCount: state.totalCount,
        launchCount: state.launchCount,
        selectedCount: state.selection.count,
        timeLabel: state.timeLabel,
        isPaused: state.isPaused,
        autoScroll: $state.autoScroll
      )
    }
    .frame(minWidth: 640, minHeight: 420)
    .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
      state.refresh()
    }
  }

  // MARK: Private

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
      Text(state.timeLabel)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Time range \(state.timeLabel)")
      Spacer()
      if state.rangeEndMilliseconds != nil {
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

}
