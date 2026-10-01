import Foundation

/// Putting the rows together: the older launches, then this one.
extension LogWindowState {

  /// Adds lines of this launch at the end, filtering only the new ones.
  /// Lines that belong earlier, from filling a gap, are merged in place.
  func appendRows(_ newRows: [LogRow]) {
    guard let first = newRows.first?.entry else { return }
    if let last = currentRows.last?.entry, first.sequence <= last.sequence {
      mergeIntoCurrent(newRows)
      return
    }
    currentRows.append(contentsOf: newRows)
    rows.append(contentsOf: newRows)
    shownRows.append(contentsOf: newRows.filter(matches))
  }

  /// Merges lines of this launch into their places by number, dropping
  /// any already held.
  func mergeIntoCurrent(_ newRows: [LogRow]) {
    let held = Set(currentRows.map(\.id))
    let added = newRows.filter { !held.contains($0.id) }
    guard !added.isEmpty else { return }
    currentRows = (currentRows + added).sorted { ($0.entry?.sequence ?? 0) < ($1.entry?.sequence ?? 0) }
    rebuildRows()
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
