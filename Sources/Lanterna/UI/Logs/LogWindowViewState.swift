import Foundation

// MARK: - Log Window View State

/// Read-only derived state for display.
///
/// Groups the labels, rows, and filter flags computed from kept
/// rows and query state, keeping the main state file focused on
/// stored state, lifecycle, actions, and loading.
extension LogWindowState {

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
    return "Live"
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

  /// When this launch started, for the Since-this-launch range.
  /// Absent before the first spill, where the range stays open
  /// and shows everything kept.
  var launchStart: Date? {
    Diagnostics.activeLaunchStartMilliseconds.map { Date(timeIntervalSince1970: Double($0) / 1_000) }
  }

}
