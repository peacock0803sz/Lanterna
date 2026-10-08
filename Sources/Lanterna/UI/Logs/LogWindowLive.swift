import Foundation

/// Taking new lines in while the window is up, and holding the list still
/// on request.
extension LogWindowState {

  /// How many waiting lines the current filters would show on resume.
  var pendingCount: Int {
    pendingRows.count(where: matches)
  }

  /// Takes in the lines written since the last look. While paused they
  /// wait; otherwise they join the list. Past the row cap the oldest
  /// lines leave whichever list took them in. Lines the mirror already
  /// dropped are not read back; only the saved file, when saving is on,
  /// still has them.
  func ingest() {
    let new = entriesAfter(lastSequence)
    guard let last = new.last else { return }
    lastSequence = last.sequence
    let newRows = new.map(LogRow.init(entry:))
    if isPaused {
      pendingRows.append(contentsOf: newRows)
      trimPendingRowsToCapacity()
    } else {
      appendRows(newRows)
    }
  }

  func pause() {
    isPaused = true
  }

  /// Shows what waited, in number order, then keeps following.
  func resume() {
    isPaused = false
    let waiting = pendingRows.sorted { ($0.entry?.sequence ?? 0) < ($1.entry?.sequence ?? 0) }
    pendingRows = []
    appendRows(waiting)
    ingest()
  }

  func togglePause() {
    if isPaused {
      resume()
    } else {
      pause()
    }
  }

  /// Follows the window on and off the screen. Coming on screen takes in
  /// whatever arrived meanwhile at once, then polls until it goes away.
  func setVisible(_ visible: Bool) {
    guard visible != isVisible else { return }
    isVisible = visible
    liveTask?.cancel()
    liveTask = nil
    guard visible else { return }
    ingest()
    let interval = liveInterval
    liveTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: interval)
        guard !Task.isCancelled, let self else { return }
        ingest()
      }
    }
  }

}
