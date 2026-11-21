import ApplicationServices

// MARK: - OtherSpaceLook

/// What the look for an application's windows on other Spaces came to.
struct OtherSpaceLook: Equatable {
  /// Whether the look ended early, out of time or on a failed read.
  var cutShort = false
  /// The windows it was sent for that it did not settle.
  var missing = Set<CGWindowID>()
}

// MARK: - AXApplicationWindowReader + other Spaces

extension AXApplicationWindowReader {
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
    expecting otherSpaceWindows: Set<CGWindowID>,
    isHidden: Bool,
    within budget: ReadBudget
  ) -> OtherSpaceLook {
    var known = Set(records.map(\.windowID))
    let wanted = otherSpaceWindows.subtracting(known)
    guard !wanted.isEmpty else {
      return OtherSpaceLook()
    }
    let probed = probeWindows(processIdentifier, wanted, budget.deadline)
    var settled = Set<CGWindowID>()
    do throws(ReadFailure) {
      for window in probed where known.insert(window.windowID).inserted {
        if
          case .record(let record) = try outcome(for: window.element, windowID: window.windowID, within: budget),
          otherSpaceWindows.contains(record.windowID) || record.isMinimized || isHidden
        {
          records.append(record)
        }
        settled.insert(window.windowID)
      }
    } catch {
      return OtherSpaceLook(cutShort: true, missing: wanted.subtracting(settled))
    }
    // The probe answers with what it found by the deadline and does not say
    // whether it stopped there.
    return OtherSpaceLook(cutShort: budget.isExpired(at: now()), missing: wanted.subtracting(settled))
  }
}
