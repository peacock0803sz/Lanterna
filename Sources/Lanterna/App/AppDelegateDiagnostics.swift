import Foundation

/// The settings' Diagnostics section: opening the log window and the
/// launches saved on disk.
extension AppDelegate {

  /// The Diagnostics section's contents, with its actions wired here.
  func makeDiagnosticsDisplay() -> DiagnosticsDisplay {
    let display = DiagnosticsDisplay()
    display.savedSummary = savedLogs?.store.usage().summary()
    display.showLogs = { [weak self] in self?.guideWindows?.openVersionLog() }
    display.deleteSavedLogs = { [weak self, weak display] in
      guard let self else { return }
      deleteSavedLogs()
      display?.savedSummary = savedLogs?.store.usage().summary()
    }
    display.applySaving = { [weak self, weak display] saving, deleting in
      guard let self else { return }
      applySavingLogs(saving, deleting: deleting)
      display?.savedSummary = savedLogs?.store.usage().summary()
    }
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

}
