import AppKit
import Darwin
import Logging

/// Application teardown, split out when the delegate reached the
/// file-length limit. Launch stays in `AppDelegate`; everything the
/// launch took is given back here, in launch order.
extension AppDelegate {
  /// Gives back everything the launch took, in that order: the system's own
  /// shortcuts first, so they return even if what follows does not.
  ///
  /// Reached twice over, once through the usual termination callback and
  /// once from a caught signal, which exits before that callback can run.
  ///
  /// May end the process rather than return, when the system's shortcuts
  /// could not be given back.
  func shutDown() {
    let restoreFailures = SystemSwitcherShortcuts.restore()
    if let line = SystemSwitcherShortcuts.summaryLine(restoring: restoreFailures) {
      Diagnostics.writeLine(line, level: .error)
    }
    hotkeys?.unregister()
    windowList?.stop()
    // Before the monitor goes, so the last thing done to the tap is taking
    // it down rather than switching it off once more. The order is not on
    // its own enough to promise that: cancelling raises a flag rather than
    // calling back a stop the actor has already been handed, so what makes
    // it hold is the loop asking again after it wakes and giving up there.
    monitorStopTask?.cancel()
    monitorStopTask = nil
    // After the restore above, never before it. The two are not equally
    // recoverable: this tap goes away with the process whatever happens
    // here, while a system shortcut left switched off outlives the process
    // that switched it off. So nothing that could fail is allowed to stand
    // between a launch and that shortcut coming back.
    monitor?.stop()
    statusMenu?.remove()
    statusMenu = nil
    // Last of the three claims this process makes on the keyboard — the
    // Carbon registration, the tap, and this monitor — and it can be: it
    // is handed events the system had already decided were this
    // process's, so it holds nothing back from anything else and leaves
    // nothing behind if the process goes without it. It is taken off all
    // the same, because a monitor outliving the presenter it answers is
    // the kind of thing that stops being harmless the moment anything
    // else is added to this teardown.
    panelKeys?.stop()
    panelKeys = nil
    if let appNapActivity {
      ProcessInfo.processInfo.endActivity(appNapActivity)
      self.appNapActivity = nil
    }

    // Reaching this exit means the process could not leave the machine
    // with both shortcuts on, and the diagnostics line saying so is easy
    // to miss in a way an exit status is not. The one that would not go
    // back on may well be off, left that way by an earlier run that was
    // killed, and the write that would have fixed it is the one that
    // failed. Both paths that reach here are the end of the process
    // anyway: the caught-signal path exits as soon as this returns, and
    // all this changes is the status it reports, while the
    // termination-callback path gives up AppKit's remaining teardown,
    // which is no loss when the windows and the run loop are going away
    // with the process regardless. The code differs from the
    // `EX_UNAVAILABLE` used at launch so the two cases stay apart.
    if !restoreFailures.isEmpty {
      exit(EX_OSERR)
    }
  }
}
