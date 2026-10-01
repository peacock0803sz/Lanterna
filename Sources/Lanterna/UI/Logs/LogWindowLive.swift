import Foundation

/// Taking new lines in while the window is up, and holding the list still
/// on request.
extension LogWindowState {

  // MARK: Internal

  /// How many waiting lines the current filters would show on resume.
  var pendingCount: Int {
    pendingRows.count(where: matches)
  }

  /// Takes in the lines written since the last look. While paused they
  /// wait; otherwise they join the list. A jump in the numbers means the
  /// mirror dropped lines before they were read, and the range is noted
  /// for filling from the saved file.
  func ingest() {
    let new = entriesAfter(lastSequence)
    guard let first = new.first, let last = new.last else { return }
    if first.sequence > lastSequence + 1 {
      noteMissing(lastSequence + 1 ... first.sequence - 1)
    }
    lastSequence = last.sequence
    let newRows = new.map(LogRow.init(entry:))
    if isPaused {
      pendingRows.append(contentsOf: newRows)
    } else {
      appendRows(newRows)
    }
  }

  func pause() {
    isPaused = true
  }

  /// Shows what waited, then keeps following.
  func resume() {
    isPaused = false
    let waiting = pendingRows
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

  // MARK: Private

  private func noteMissing(_ range: ClosedRange<UInt64>) {
    missingRanges.append(range)
  }

}
