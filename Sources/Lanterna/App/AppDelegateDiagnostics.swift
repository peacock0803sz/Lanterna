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
    return display
  }

  /// Deletes the launches saved before this one, then has the log window
  /// read the saved launches again.
  func deleteSavedLogs() {
    guard let savedLogs else { return }
    savedLogs.deleteEarlierLaunches()
    guideWindows?.logState.invalidateSavedLaunches()
  }

}
