import Foundation
import Logging
import Observation

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

// MARK: - LogWindowState

/// What the log window shows and how it is filtered.
///
/// Held by `GuideWindows` for the whole run, so closing the window keeps
/// the filters, the columns and the rows already read.
@MainActor
@Observable
final class LogWindowState {

  // MARK: Lifecycle

  /// `readEntries` returns the mirror, oldest first; tests pass their own.
  init(readEntries: @escaping @MainActor () -> [Diagnostics.LogEntry] = { Diagnostics.recentEntries }) {
    self.readEntries = readEntries
  }

  // MARK: Internal

  /// The rows the filters let through, oldest first.
  private(set) var shownRows = [LogRow]()

  var selection = Set<LogRow.ID>()

  /// Every row read for the current scope, oldest first.
  private(set) var rows = [LogRow]() {
    didSet { recomputeShownRows() }
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

  /// Reads the mirror again and shows it.
  func reload() {
    rows = readEntries().map(LogRow.init(entry:))
  }

  // MARK: Private

  private let readEntries: @MainActor () -> [Diagnostics.LogEntry]

  private func recomputeShownRows() {
    shownRows = rows
  }

}
