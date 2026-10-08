import Foundation

// MARK: - SavedLaunchEntries

/// One saved launch's lines, read back.
struct SavedLaunchEntries: Sendable {
  let launch: LaunchID
  let entries: [Diagnostics.LogEntry]
}

// MARK: - SavedLaunchBatch

/// The newest saved launches but this one, within the read limits, with
/// what reading them skipped and how many bytes they took.
struct SavedLaunchBatch: Sendable {
  var launches = [SavedLaunchEntries]()
  var skippedLines = 0
  var unreadableFiles = 0
  /// Bytes taken from the files, headers included.
  var bytesRead = 0
}

// MARK: - SavedLogReadLimits

/// How much of the saved launches the log window reads: the newest
/// `launchCount` launches within `byteBudget` bytes altogether.
struct SavedLogReadLimits: Equatable, Sendable {
  var launchCount: Int
  var byteBudget: Int
}

// MARK: - SavedLogSource

/// How the log window reaches the saved launches. Closures so the tests
/// can stand in a folder of their own.
struct SavedLogSource: Sendable {
  /// This launch's file while its lines are being saved, nil otherwise.
  let currentFile: @MainActor @Sendable () -> URL?
  /// The newest saved launches but the file at `excluding`, oldest first,
  /// within the limits the source was made with.
  let readOthers: @Sendable (_ excluding: URL?) -> SavedLaunchBatch
}

extension SavedLogSource {
  /// Reads `store`, with this launch's file as the diagnostics name it.
  /// The newest file alone over the budget is read by its tail; a later
  /// file that would pass the budget stops the reading, and older files
  /// past the launch count are never opened. Files left unread by the
  /// limits count as neither skipped nor unreadable.
  static func live(
    store: LaunchLogStore,
    limits: SavedLogReadLimits = SavedLogReadLimits(
      launchCount: LaunchLogStore.readLaunchLimit,
      byteBudget: LaunchLogStore.readByteLimit
    )
  ) -> SavedLogSource {
    SavedLogSource(
      currentFile: { Diagnostics.savingTo },
      readOthers: { excluding in
        var batch = SavedLaunchBatch()
        let files = store.files()
          .filter { $0.url.standardizedFileURL != excluding?.standardizedFileURL }
          .suffix(limits.launchCount)
        var budget = limits.byteBudget
        var isNewest = true
        var launches = [SavedLaunchEntries]()
        for file in files.reversed() {
          if isNewest {
            isNewest = false
            if file.byteCount > budget {
              let read = store.readTail(file, budget: budget)
              guard read.isReadable else {
                batch.unreadableFiles += 1
                continue
              }
              batch.skippedLines += read.skippedLines
              batch.bytesRead += read.byteCount
              budget -= read.byteCount
              launches.append(SavedLaunchEntries(launch: file.launch, entries: read.entries))
              continue
            }
          } else if file.byteCount > budget {
            break
          }
          let read = store.read(file)
          guard read.isReadable else {
            batch.unreadableFiles += 1
            continue
          }
          batch.skippedLines += read.skippedLines
          batch.bytesRead += read.byteCount
          budget -= read.byteCount
          launches.append(SavedLaunchEntries(launch: file.launch, entries: read.entries))
        }
        batch.launches = launches.reversed()
        return batch
      }
    )
  }
}

// MARK: - LogWindowState + scope

/// Reading the saved launches for All launches. This launch's lines the
/// mirror dropped are not read back: past the row cap the live list lets
/// them go, and only the saved file, when saving is on, still has them.
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
    savedLogsBytesRead = 0
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

  /// Reads the newest saved launches but this one in the background, then
  /// shows them, unless the scope moved on meanwhile.
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
      savedLogsBytesRead = batch.bytesRead
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
