import ApplicationServices

// MARK: - LiveWindowSwitcher + Raise Alone

/// Brings only the chosen window forward, ahead of its application.
///
/// Activating an application can bring another of its windows forward
/// along with the chosen one, which on another display can cover a window
/// being worked in. Making the chosen window the main one and raising it
/// ahead of the activation tries to leave the other windows where they
/// were. Only the chosen element is ever touched: nothing here lists or
/// addresses any other window.
///
/// The preparing writes, making the chosen window main and raising it
/// early, prepare rather than take, so a failing one still leaves a
/// switched take with a note. Only the first failing preparation is
/// named: a main-window failure hides a raise failure after it, which is
/// what the `excuse == nil` check keeps. Past the preparations, a failure
/// fails the take itself, worded as it is with the switch off.
extension LiveWindowSwitcher {

  // MARK: Internal

  func switchRaiseAlone(_ target: ActivationTarget, resolved: AXUIElement) -> ActivationReport {
    var excuse: String?
    if let failure = write(resolved, setMain) {
      excuse = "main window \(words(for: failure))"
    }
    if let failure = write(resolved, raiseWindow), excuse == nil {
      excuse = "raise \(words(for: failure))"
    }
    if let failure = activate(target) {
      return ActivationReport(outcome: .failed(failure), reopen: nil, raiseAlone: nil)
    }
    if let failure = unminimize(resolved) {
      return ActivationReport(outcome: .failed(failure), reopen: nil, raiseAlone: nil)
    }
    if let failure = raise(resolved) {
      return ActivationReport(outcome: .failed(failure), reopen: nil, raiseAlone: nil)
    }
    if let excuse {
      return ActivationReport(outcome: .switched, reopen: nil, raiseAlone: .notHeld(reason: excuse))
    }
    return ActivationReport(outcome: .switched, reopen: nil, raiseAlone: .held)
  }

  // MARK: Private

  /// The failure's own wording, so the note names the step and the cause
  /// together.
  private func words(for failure: ActivationFailure) -> String {
    switch failure {
    case .timedOut:
      "timed out"
    case .other(let reason):
      reason
    case .windowGone:
      "window gone"
    case .applicationGone:
      "application gone"
    }
  }

}
