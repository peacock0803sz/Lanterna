import Foundation

/// The settings' Diagnostics section: opening the log window and the
/// launches saved on disk.
extension AppDelegate {

  // MARK: Internal

  /// The Diagnostics section's contents, with its actions wired here.
  func makeDiagnosticsDisplay() -> DiagnosticsDisplay {
    let display = DiagnosticsDisplay()
    display.savedSummary = savedLogs?.store.usage().summary()
    display.showLogs = { [weak self] in self?.guideWindows?.openVersionLog() }
    display.deleteSavedLogs = { [weak self, weak display] in
      guard let self else { return }
      deleteSavedLogs()
      display?.savedSummary = savedLogs?.store.usage().summary()
      display?.refreshRetention()
    }
    display.applySaving = { [weak self, weak display] saving, deleting in
      guard let self else { return }
      applySavingLogs(saving, deleting: deleting)
      display?.savedSummary = savedLogs?.store.usage().summary()
      display?.refreshRetention()
    }
    display.refreshRetention = { [weak self, weak display] in
      display?.retention = self?.retentionSnapshot()
    }
    display.retention = retentionSnapshot()
    return display
  }

  /// Switches saving on or off for the rest of the run, and keeps the log
  /// window's choice of launches in step with it.
  func applySavingLogs(_ saving: Bool, deleting: Bool) {
    savedLogs?.setSaving(saving, deletingSaved: deleting)
    guideWindows?.logState.setSavingEnabled(saving)
    if deleting {
      guideWindows?.logState.invalidateSavedLaunches()
    }
  }

  /// Deletes the launches saved before this one, then has the log window
  /// read the saved launches again.
  func deleteSavedLogs() {
    guard let savedLogs else { return }
    savedLogs.deleteEarlierLaunches()
    guideWindows?.logState.invalidateSavedLaunches()
  }

  // MARK: Private

  /// What this run holds onto, or nil when the log window is not up.
  /// Read fresh every time the settings open, so the numbers are the
  /// latest rather than the ones from the last opening.
  private func retentionSnapshot() -> RetentionSnapshot? {
    guard let logState = guideWindows?.logState else { return nil }
    return RetentionCounts.snapshot(
      logState: logState,
      shortcutMemoryCount: presenter?.keyCommands.shortcutMemoryCount ?? 0,
      shortcutMemoryLimit: presenter?.keyCommands.shortcutMemoryLimit ?? 0,
      mruRecordCount: presenter?.tracker.recordCount ?? 0,
      mruApplicationCount: presenter?.tracker.applicationSequenceCount ?? 0
    )
  }

}
