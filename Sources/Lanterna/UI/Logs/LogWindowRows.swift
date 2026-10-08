import Foundation

/// Putting the rows together: the older launches, then this one.
extension LogWindowState {

  /// Adds lines of this launch at the end, filtering only the new ones.
  /// Past the row cap the oldest-numbered lines leave, from the live
  /// lists alone; the saved rows stay as read.
  func appendRows(_ newRows: [LogRow]) {
    guard !newRows.isEmpty else { return }
    currentRows.append(contentsOf: newRows)
    rows.append(contentsOf: newRows)
    shownRows.append(contentsOf: newRows.filter(matches))
    trimCurrentRowsToCapacity()
  }

  /// Lays the rows out again for the scope: this launch alone, or every
  /// saved launch with a separator opening each.
  func rebuildRows() {
    switch scope {
    case .thisLaunch:
      rows = currentRows
    case .allLaunches:
      rows = olderRows + [LogRow(separatorFor: currentLaunch)] + currentRows
    }
    recomputeShownRows()
  }

  /// Filters every row again, after a filter changed.
  func recomputeShownRows() {
    shownRows = rows.filter(matches)
  }

}
