import Foundation

// MARK: - Log Window Time Navigation

extension LogWindowState {

  // MARK: Internal

  func showLatest() {
    resetTime()
    isPaused = false
    pendingCount = 0
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

  // MARK: Private

  private func rewriteTimeTokens(with tokens: [String]) {
    let kept = splitLogQueryTokens(query.lightweightText).filter { entry in
      guard let key = logQueryKey(of: entry)?.lowercased() else { return true }
      return key != "after" && key != "before"
    }
    pickerTimeTokens = Set(tokens)
    query.lightweightText = (kept + tokens).joined(separator: " ")
  }

}
