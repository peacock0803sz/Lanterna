import ApplicationServices

// MARK: - OtherSpaceLook

/// What the look for an application's windows on other Spaces came to.
struct OtherSpaceLook: Equatable {
  /// Whether the look ended early, out of time or on a failed read.
  var cutShort = false
  /// The windows it was sent for that it did not settle.
  var missing = Set<CGWindowID>()
  /// Whether the application, asked after the missing windows, answered
  /// both its main and its focused window with an explicit "no value".
  var namesNoWindow = false
}

// MARK: - AXApplicationWindowReader + other Spaces

extension AXApplicationWindowReader {

  // MARK: Internal

  /// Adds the windows the application's list left out, those on Spaces no
  /// display is showing.
  ///
  /// Only the windows the window server keeps on a hidden Space and the list
  /// lacks are looked for, and the look stops once all of them have turned
  /// up: an application with every window in its list costs no probe at
  /// all. A window counts as settled once the rule table has judged it,
  /// whether it became a record or was excluded; one the probe returned but
  /// the look ran out of time or failed before judging is still missing.
  ///
  /// A window still missing after the probe is asked after by name: the
  /// application's main and focused windows reach a window on a hidden Space
  /// at any element id, where the probe only tries a range of them. A
  /// Chromium-based browser numbered its window past that range. Only the
  /// windows still missing are taken from those answers. An application
  /// that answers both with an explicit "no value" is said to name no
  /// window: one that closed a window but kept it on a hidden Space
  /// answered so, where every application seen with a real window there
  /// named it. A refusal is not that answer.
  ///
  /// The probe also turns up windows the window server keeps on no hidden
  /// Space: an unselected tab, a closed window the application keeps, a
  /// panel it is not showing. Listing them would put rows in the panel for
  /// windows the user cannot see, so a found window is listed only when the
  /// window server keeps it elsewhere. A minimized window and the windows of
  /// a hidden application are listed regardless, because whether those keep
  /// their Space is not something the window server's answer settles, and an
  /// unknown is not a reason to drop a row.
  ///
  /// Best effort: the list already read is a complete answer, so a budget
  /// spent or a failure while probing keeps it instead of discarding the
  /// application for a bonus.
  func appendOtherSpaceRecords(
    to records: inout [WindowRecord],
    of processIdentifier: pid_t,
    through application: AXUIElement,
    expecting otherSpaceWindows: Set<CGWindowID>,
    isHidden: Bool,
    within budget: ReadBudget
  ) -> OtherSpaceLook {
    var known = Set(records.map(\.windowID))
    let wanted = otherSpaceWindows.subtracting(known)
    guard !wanted.isEmpty else {
      return OtherSpaceLook()
    }
    var settled = Set<CGWindowID>()
    func judge(_ window: ProbedWindow) throws(ReadFailure) {
      guard known.insert(window.windowID).inserted else { return }
      if
        case .record(let record) = try outcome(for: window.element, windowID: window.windowID, within: budget),
        otherSpaceWindows.contains(record.windowID) || record.isMinimized || isHidden
      {
        records.append(record)
      }
      settled.insert(window.windowID)
    }
    var namesNoWindow = false
    do throws(ReadFailure) {
      for window in probeWindows(processIdentifier, wanted, budget.deadline) {
        try judge(window)
      }
      let remaining = wanted.subtracting(settled)
      if !remaining.isEmpty {
        let named = try namedWindows(of: application, within: budget)
        namesNoWindow = named.answeredNone
        for window in named.windows where remaining.contains(window.windowID) {
          try judge(window)
        }
      }
    } catch {
      return OtherSpaceLook(cutShort: true, missing: wanted.subtracting(settled))
    }
    // The probe answers with what it found by the deadline and does not say
    // whether it stopped there.
    return OtherSpaceLook(
      cutShort: budget.isExpired(at: now()),
      missing: wanted.subtracting(settled),
      namesNoWindow: namesNoWindow
    )
  }

  // MARK: Private

  /// The application's main and focused windows, each once, and whether
  /// both answers were an explicit "no value". Only that answer was seen
  /// from a window closed but kept; a refusal says nothing about windows.
  private func namedWindows(
    of application: AXUIElement,
    within budget: ReadBudget
  ) throws(ReadFailure) -> (windows: [ProbedWindow], answeredNone: Bool) {
    var named = [ProbedWindow]()
    var answeredNone = true
    for name in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
      let (error, value) = try send(name, to: application, within: budget)
      answeredNone = answeredNone && error == .noValue
      guard
        error == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID()
      else { continue }
      let element = unsafeDowncast(value, to: AXUIElement.self)
      try prepare(element)
      guard
        let windowID = try windowID(of: element, within: budget),
        !named.contains(where: { $0.windowID == windowID })
      else { continue }
      named.append(ProbedWindow(element: element, windowID: windowID))
    }
    return (named, answeredNone)
  }

}
