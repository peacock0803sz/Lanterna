import Foundation
import Logging
import Observation
import SwiftUI

// MARK: - LogRow

/// One row of the log table: a line, or the separator that opens a launch.
struct LogRow: Identifiable, Equatable, Sendable {

  // MARK: Lifecycle

  init(entry: Diagnostics.LogEntry) {
    launch = entry.launch
    self.entry = entry
    id = "\(entry.launch.stamp)#\(entry.sequence)"
  }

  /// The separator row that opens `launch`.
  init(separatorFor launch: LaunchID) {
    self.launch = launch
    entry = nil
    id = "\(launch.stamp)#0"
  }

  // MARK: Internal

  let id: String
  let launch: LaunchID
  /// The line, or nil for a separator.
  let entry: Diagnostics.LogEntry?

  var isSeparator: Bool {
    entry == nil
  }

}

// MARK: - Diagnostics.LogEntry + oneLineMessage

extension Diagnostics.LogEntry {
  /// The message on one line: each line break becomes `⏎`, so a row and a
  /// copied line never split in two.
  var oneLineMessage: String {
    message
      .replacing("\r\n", with: "⏎")
      .replacing("\n", with: "⏎")
      .replacing("\r", with: "⏎")
  }
}

// MARK: - LaunchScope

/// Which launches the log window shows.
enum LaunchScope: String, CaseIterable, Sendable {
  case thisLaunch
  case allLaunches

  var title: String {
    switch self {
    case .thisLaunch: "This launch"
    case .allLaunches: "All launches"
    }
  }
}

// MARK: - LevelFloor

/// The lightest level the log window shows; every heavier one shows too.
enum LevelFloor: String, CaseIterable, Sendable {
  case debug
  case info
  case warning
  case error

  // MARK: Internal

  var level: Logger.Level {
    switch self {
    case .debug: .debug
    case .info: .info
    case .warning: .warning
    case .error: .error
    }
  }

  var title: String {
    switch self {
    case .debug: "Debug and above"
    case .info: "Info and above"
    case .warning: "Warnings & Errors"
    case .error: "Errors only"
    }
  }
}

// MARK: - LogWindowState

/// What the log window shows and how it is filtered.
///
/// Held by `GuideWindows` for the whole run, so closing the window keeps
/// the filters, the columns and the rows already read.
@MainActor
@Observable
final class LogWindowState {

  // MARK: Lifecycle

  /// `entriesAfter` returns the mirrored lines numbered after the given
  /// one, oldest first; tests pass their own.
  init(
    entriesAfter: @escaping @MainActor (UInt64) -> [Diagnostics.LogEntry] = { Diagnostics.entries(after: $0) },
    currentLaunch: LaunchID = Diagnostics.currentLaunch,
    savedLogs: SavedLogSource? = nil,
    writeLine: @escaping @MainActor (LogLine) -> Void = { Diagnostics.writeLine($0) },
    liveInterval: Duration = .milliseconds(250)
  ) {
    self.entriesAfter = entriesAfter
    self.currentLaunch = currentLaunch
    self.savedLogs = savedLogs
    self.writeLine = writeLine
    self.liveInterval = liveInterval
  }

  /// Reads the whole mirror through `readEntries`, for tests that do not
  /// care about polling.
  convenience init(readEntries: @escaping @MainActor () -> [Diagnostics.LogEntry]) {
    self.init(entriesAfter: { after in readEntries().filter { $0.sequence > after } })
  }

  // MARK: Internal

  /// How many of this launch's lines `currentRows` and `pendingRows`
  /// each hold at most. Tied to the mirror's capacity, so neither list
  /// holds more of this launch's lines than the mirror does; the saved
  /// launches in
  /// `olderRows` are bounded separately by how much is read from disk.
  static let rowsCapacity = DiagnosticLog.capacity

  /// Every row read for the current scope, oldest first.
  var rows = [LogRow]()

  /// The rows the filters let through, oldest first.
  var shownRows = [LogRow]()

  /// This launch's lines taken in, by number.
  var currentRows = [LogRow]()

  /// The saved launches before this one, each opened by its separator.
  /// Kept once read, so switching back and forth reads the disk once.
  var olderRows = [LogRow]()

  /// Whether the older launches have been read since they last changed.
  var hasReadOlder = false

  /// Bytes taken from the saved launches on the last read, headers
  /// included. Back to zero once the older rows are forgotten.
  var savedLogsBytesRead = 0
  /// True while saved launches are being read.
  var isLoading = false

  /// Whether Save logs to disk is on. Off offers this launch alone.
  var isSavingEnabled = true

  var selection = Set<LogRow.ID>()

  /// Whether the list holds still. Lines still arrive and wait in
  /// `pendingRows` until the reader resumes.
  var isPaused = false

  /// Lines that arrived while paused, oldest first. Held only up to the
  /// row cap, so a long pause still lets the oldest waiting lines go;
  /// what the mirror dropped meanwhile is not read back, and only the
  /// saved file, when saving is on, still has it.
  var pendingRows = [LogRow]()

  /// Whether the window is on screen. Polling runs only while it is.
  var isVisible = false

  /// The number of the newest line of this launch taken in, in `rows` or
  /// in `pendingRows`.
  var lastSequence: UInt64 = 0

  @ObservationIgnored let entriesAfter: @MainActor (UInt64) -> [Diagnostics.LogEntry]
  @ObservationIgnored let currentLaunch: LaunchID
  @ObservationIgnored let savedLogs: SavedLogSource?
  @ObservationIgnored let writeLine: @MainActor (LogLine) -> Void
  @ObservationIgnored let liveInterval: Duration
  @ObservationIgnored var liveTask: Task<Void, Never>?
  @ObservationIgnored var olderTask: Task<Void, Never>?

  /// Which fixed columns show, in what order and how wide, as the table
  /// keeps it.
  var columnCustomization = TableColumnCustomization<LogRow>()

  /// The context keys shown as columns, in name order. Kept when the rows
  /// in range no longer carry them.
  var contextColumns = [String]()

  /// Text a line's message has to hold, in any case. Empty lets every
  /// line through.
  var searchText = "" {
    didSet {
      if searchText != oldValue {
        recomputeShownRows()
      }
    }
  }

  /// The lightest level shown.
  var levelFloor = LevelFloor.debug {
    didSet {
      if levelFloor != oldValue {
        recomputeShownRows()
      }
    }
  }

  /// The one category shown, or nil for all of them.
  var category: LogCategory? {
    didSet {
      if category != oldValue {
        recomputeShownRows()
      }
    }
  }

  /// This launch, or every saved one.
  var scope = LaunchScope.thisLaunch {
    didSet {
      if scope != oldValue {
        scopeChanged()
      }
    }
  }

  /// Lines among `rows`, separators not counted.
  var entryCount: Int {
    rows.count { !$0.isSeparator }
  }

  /// Lines among `shownRows`, separators not counted.
  var shownEntryCount: Int {
    shownRows.count { !$0.isSeparator }
  }

  /// Selected lines that are on screen. A selection hidden by a filter
  /// does not count, and neither does a separator.
  var selectedCount: Int {
    selectedEntries.count
  }

  /// The selected lines that are on screen, oldest first.
  var selectedEntries: [Diagnostics.LogEntry] {
    guard !selection.isEmpty else { return [] }
    return shownRows.compactMap { selection.contains($0.id) ? $0.entry : nil }
  }

  /// The line the detail pane shows: there is one only while exactly one
  /// line, not a separator, is selected.
  var detailEntry: Diagnostics.LogEntry? {
    guard selection.count == 1, let id = selection.first else { return nil }
    return rows.first { $0.id == id }?.entry
  }

  /// Whether any filter is narrowing the list.
  var isFiltering: Bool {
    !searchText.isEmpty || levelFloor != .debug || category != nil
  }

  /// Drops the oldest-numbered rows past the cap from `currentRows`, and
  /// takes the same rows out of `rows` and `shownRows` by difference.
  /// Selections of the dropped rows go with them, so the selection never
  /// points at rows the window no longer holds.
  /// The saved `olderRows` are never touched; full refiltering is left
  /// to the caller that needs it.
  func trimCurrentRowsToCapacity() {
    guard currentRows.count > Self.rowsCapacity else { return }
    let ordered = currentRows.sorted { ($0.entry?.sequence ?? 0) < ($1.entry?.sequence ?? 0) }
    let kept = Array(ordered.suffix(Self.rowsCapacity))
    let keptIDs = Set(kept.map(\.id))
    let evicted = Set(currentRows.map(\.id)).subtracting(keptIDs)
    currentRows = kept
    guard !evicted.isEmpty else { return }
    rows.removeAll { evicted.contains($0.id) }
    shownRows.removeAll { evicted.contains($0.id) }
    selection.subtract(evicted)
  }

  /// Drops the oldest-numbered waiting lines past the cap. The shown
  /// `currentRows` stay as they are while paused.
  func trimPendingRowsToCapacity() {
    guard pendingRows.count > Self.rowsCapacity else { return }
    pendingRows = Array(
      pendingRows.sorted { ($0.entry?.sequence ?? 0) < ($1.entry?.sequence ?? 0) }.suffix(Self.rowsCapacity)
    )
  }

  /// Whether the filters let `row` through: its level reaches the floor,
  /// its category is the one picked (or any), and its message holds the
  /// search text in any case. Separators always stay, so a launch's lines
  /// still read under their heading.
  func matches(_ row: LogRow) -> Bool {
    guard let entry = row.entry else { return true }
    guard entry.level >= levelFloor.level else { return false }
    if let category, entry.category != category {
      return false
    }
    return searchText.isEmpty || entry.message.range(of: searchText, options: .caseInsensitive) != nil
  }

}
