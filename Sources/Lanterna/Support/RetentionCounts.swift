import Foundation

// MARK: - RetentionSnapshot

/// Everything the process holds onto, counted for the diagnostics. Items
/// with a limit read as `current/limit`; watched items carry no limit.
struct RetentionSnapshot: Equatable, Sendable {
  /// This launch's live log rows.
  var liveRows: Int
  var liveRowsLimit: Int
  /// Log lines that arrived while paused.
  var waitingRows: Int
  var waitingRowsLimit: Int
  /// Whether the log list is holding still. Only then is the waiting
  /// count shown beside the live one.
  var logPaused: Bool
  /// Bytes taken from the saved launches on the last read.
  var savedBytes: Int
  var savedBytesLimit: Int
  /// Remembered shortcut rows.
  var shortcutCount: Int
  var shortcutLimit: Int
  /// Cached application icons. Watched, not capped.
  var iconCount: Int
  /// Remembered window and application uses. Watched, not capped.
  var mruRecords: Int
  var mruApplications: Int
  /// The mirrored diagnostic lines.
  var mirrorRows: Int
  var mirrorRowsLimit: Int
}

// MARK: - RetentionCounts

/// Gathers one retention snapshot from the owners.
enum RetentionCounts {

  /// Reads the current numbers. The limits ride on the same constants as
  /// the caps themselves, so the two cannot drift apart.
  @MainActor
  static func snapshot(
    logState: LogWindowState,
    shortcutMemoryCount: Int,
    shortcutMemoryLimit: Int,
    mruRecordCount: Int,
    mruApplicationCount: Int,
    iconCount: Int = AppIconResolver.cachedCount,
    mirrorCount: Int = Diagnostics.recentEntries.count
  ) -> RetentionSnapshot {
    RetentionSnapshot(
      liveRows: logState.currentRows.count,
      liveRowsLimit: LogWindowState.rowsCapacity,
      waitingRows: logState.pendingRows.count,
      waitingRowsLimit: LogWindowState.rowsCapacity,
      logPaused: logState.isPaused,
      savedBytes: logState.savedLogsBytesRead,
      savedBytesLimit: LaunchLogStore.readByteLimit,
      shortcutCount: shortcutMemoryCount,
      shortcutLimit: shortcutMemoryLimit,
      iconCount: iconCount,
      mruRecords: mruRecordCount,
      mruApplications: mruApplicationCount,
      mirrorRows: mirrorCount,
      mirrorRowsLimit: DiagnosticLog.capacity
    )
  }

}
