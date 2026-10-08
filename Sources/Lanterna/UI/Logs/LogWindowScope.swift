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
  /// Every saved launch but the file at `excluding`, oldest first.
  let readOthers: @Sendable (_ excluding: URL?) -> SavedLaunchBatch
}

extension SavedLogSource {
  /// Reads `store`, with this launch's file as the diagnostics name it.
  static func live(store: LaunchLogStore) -> SavedLogSource {
    SavedLogSource(
      currentFile: { Diagnostics.savingTo },
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

/// Reading the saved launches for All launches. Lines the mirror dropped
/// stay on disk alone: past the row cap the live list lets them go rather
/// than reading them back.
extension LogWindowState {

  // MARK: Internal

  /// Whether All launches can be offered at all.
  var hasSavedLogs: Bool {
    savedLogs != nil && isSavingEnabled
  }

  /// Follows Save logs to disk: off fixes the scope to this launch.
  func setSavingEnabled(_ enabled: Bool) {
    isSavingEnabled = enabled
    if !enabled {
      scope = .thisLaunch
    }
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

  func scopeChanged() {
    if scope == .allLaunches, !hasSavedLogs {
      scope = .thisLaunch
      return
    }
    olderTask?.cancel()
    olderTask = nil
    isLoading = false
    if scope == .allLaunches, !hasReadOlder {
      loadOlder()
    } else {
      rebuildRows()
    }
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
