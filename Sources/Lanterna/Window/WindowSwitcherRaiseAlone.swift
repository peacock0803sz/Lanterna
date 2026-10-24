import ApplicationServices

// MARK: - LiveWindowSwitcher + Raise Alone

/// Brings only the chosen window forward, ahead of its application.
///
/// The platform brings the application's main window along when an
/// application comes forward, which on another display can cover a window
/// being worked in. Making the chosen window the main one first and
/// raising it ahead of the activation leaves that older window where it
/// was. Only the chosen element is ever touched: nothing here lists or
/// addresses any other window.
///
/// The first two writes prepare rather than take, so either may fail and
/// still leave a switched take: the note then says which half did not
/// hold. Anything later fails the take itself, in the old words.
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
  /// together. Only the first failing preparation is named.
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
