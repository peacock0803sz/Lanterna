import Foundation

// MARK: - SavedLaunchEntries

/// One saved launch's lines, read back.
struct SavedLaunchEntries: Sendable {
  let launch: LaunchID
  let entries: [Diagnostics.LogEntry]
}

// MARK: - SavedLaunchBatch

/// Every saved launch but this one, with what reading them skipped.
struct SavedLaunchBatch: Sendable {
  var launches = [SavedLaunchEntries]()
  var skippedLines = 0
  var unreadableFiles = 0
}

// MARK: - SavedLogSource

/// How the log window reaches the saved launches. Closures so the tests
/// can stand in a folder of their own.
struct SavedLogSource: Sendable {
  /// This launch's file while its lines are being saved, nil otherwise.
  let currentFile: @MainActor @Sendable () -> URL?
  /// This launch's file, its lines named as `launch`.
  let readCurrent: @Sendable (_ url: URL, _ launch: LaunchID) -> SavedLaunchRead
  /// Every saved launch but the file at `excluding`, oldest first.
  let readOthers: @Sendable (_ excluding: URL?) -> SavedLaunchBatch
}

extension SavedLogSource {
  /// Reads `store`, with this launch's file as the diagnostics name it.
  static func live(store: LaunchLogStore) -> SavedLogSource {
    SavedLogSource(
      currentFile: { Diagnostics.savingTo },
      readCurrent: { url, launch in
        store.read(SavedLaunchFile(url: url, launch: launch, byteCount: 0))
      },
      readOthers: { excluding in
        var batch = SavedLaunchBatch()
        for file in store.files() where file.url.standardizedFileURL != excluding?.standardizedFileURL {
          let read = store.read(file)
          guard read.isReadable else {
            batch.unreadableFiles += 1
            continue
          }
          batch.skippedLines += read.skippedLines
          batch.launches.append(SavedLaunchEntries(launch: file.launch, entries: read.entries))
        }
        return batch
      }
    )
  }
}

// MARK: - LogWindowState + scope

/// Reading the saved launches: the older ones for All launches, and this
/// launch's own file for the lines the mirror dropped before they were
/// taken in.
extension LogWindowState {

  // MARK: Internal

  /// Whether All launches can be offered at all.
  var hasSavedLogs: Bool {
    savedLogs != nil
  }

  /// Forgets the older launches read so far, after they changed on disk,
  /// and reads them again if they are showing.
  func invalidateSavedLaunches() {
    olderTask?.cancel()
    olderTask = nil
    olderRows = []
    hasReadOlder = false
    if scope == .allLaunches {
      loadOlder()
    } else {
      rebuildRows()
    }
  }

  /// Fills the numbers of this launch the mirror dropped, from this
  /// launch's file. Skipped while nothing is being saved; a range looked
  /// for once is not looked for again, found or not.
  func fillMissingIfNeeded() {
    guard fillTask == nil, !missingRanges.isEmpty else { return }
    guard let savedLogs, let url = savedLogs.currentFile() else {
      missingRanges = []
      return
    }
    let ranges = missingRanges
    missingRanges = []
    filledRanges.append(contentsOf: ranges)
    let launch = currentLaunch
    fillTask = Task { [weak self] in
      let read = await Task.detached { savedLogs.readCurrent(url, launch) }.value
      guard let self else { return }
      fillTask = nil
      let found = read.entries
        .filter { entry in ranges.contains { $0.contains(entry.sequence) } }
        .map(LogRow.init(entry:))
      reportSkipped(lines: read.skippedLines, files: read.isReadable ? 0 : 1)
      if isPaused {
        pendingRows.append(contentsOf: found)
      } else {
        mergeIntoCurrent(found)
      }
      fillMissingIfNeeded()
    }
  }

  func scopeChanged() {
    olderTask?.cancel()
    olderTask = nil
    isLoading = false
    if scope == .allLaunches, !hasReadOlder {
      loadOlder()
    } else {
      rebuildRows()
    }
    fillMissingIfNeeded()
  }

  /// Reads every saved launch but this one in the background, then shows
  /// them, unless the scope moved on meanwhile.
  func loadOlder() {
    guard let savedLogs else {
      rebuildRows()
      return
    }
    isLoading = true
    rebuildRows()
    let excluding = savedLogs.currentFile()
    olderTask = Task { [weak self] in
      let batch = await Task.detached { savedLogs.readOthers(excluding) }.value
      guard let self, !Task.isCancelled, scope == .allLaunches else { return }
      olderTask = nil
      isLoading = false
      hasReadOlder = true
      olderRows = batch.launches.flatMap { launch in
        [LogRow(separatorFor: launch.launch)] + launch.entries.map(LogRow.init(entry:))
      }
      rebuildRows()
      reportSkipped(lines: batch.skippedLines, files: batch.unreadableFiles)
    }
  }

  // MARK: Private

  /// One line per read that skipped anything, so a damaged file is known
  /// without flooding the log.
  private func reportSkipped(lines: Int, files: Int) {
    guard lines > 0 || files > 0 else { return }
    writeLine(LogLine(
      .warning,
      .logs,
      "logs: reading saved logs skipped \(lines) damaged lines and \(files) unreadable files",
      context: ["skippedLines": .int(lines), "unreadableFiles": .int(files)]
    ))
  }

}
