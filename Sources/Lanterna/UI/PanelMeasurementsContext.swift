import Foundation

// MARK: - Measurement context

/// The values a measurement line carries beside its wording, so the log
/// window can line them up in columns. Only what the measurement already
/// holds: nothing here reads a window or an application.
extension Diagnostics {
  /// A duration in whole milliseconds, rounded to the nearest.
  static func wholeMilliseconds(_ duration: Duration) -> Int {
    let milliseconds = Double(duration.components.seconds) * 1000
      + Double(duration.components.attoseconds) * 1e-15
    return Int(milliseconds.rounded())
  }
}

extension HotkeyMeasurement {
  /// The badge read rides along only when the badges are on, so a panel
  /// shown without them carries exactly the columns it always did.
  var context: [String: ContextValue] {
    var context: [String: ContextValue] = ["ms": .int(Diagnostics.wholeMilliseconds(elapsed))]
    if let badgeReading {
      context["badges"] = .string(badgeReading.outcome.word)
      context["badgeMs"] = .int(Diagnostics.wholeMilliseconds(badgeReading.elapsed))
    }
    return context
  }
}

extension BadgeReading.Outcome {
  /// How the log names the outcome. The reason a read failed goes on its
  /// own warning line, so the column stays one of a few words.
  var word: String {
    switch self {
    case .read: "read"
    case .late: "late"
    case .failed: "failed"
    case .noDock: "noDock"
    }
  }
}

extension PanelExitMeasurement {
  var context: [String: ContextValue] {
    ["ms": .int(Diagnostics.wholeMilliseconds(elapsed))]
  }
}

extension SwitchMeasurement {

  // MARK: Internal

  /// `bundle` comes from the list on screen and is left out when the row
  /// was not found there.
  func context(processIdentifier: pid_t, bundle: String?) -> [String: ContextValue] {
    var context: [String: ContextValue] = [
      "app": .string(appName),
      "pid": .int(Int(processIdentifier)),
      "window": .string(displayTitle),
      "result": .string(resultWord),
      "ms": .int(Diagnostics.wholeMilliseconds(elapsed)),
    ]
    if let windowID = id.windowID {
      context["windowId"] = .string(String(format: "0x%x", windowID))
    }
    if let bundle {
      context["bundle"] = .string(bundle)
    }
    if let reopen {
      switch reopen {
      case .requested:
        context["reopen"] = .string("requested")
      case .skippedNoBundle:
        context["reopen"] = .string("skippedNoBundle")
      }
    }
    if let raiseAlone {
      switch raiseAlone {
      case .held:
        context["raiseAlone"] = .string("held")
      case .notHeld:
        context["raiseAlone"] = .string("notHeld")
      }
    }
    return context
  }

  // MARK: Private

  private var resultWord: String {
    switch outcome {
    case .switched: "ok"
    case .failed(.timedOut): "timedOut"
    case .failed: "failed"
    }
  }

}
