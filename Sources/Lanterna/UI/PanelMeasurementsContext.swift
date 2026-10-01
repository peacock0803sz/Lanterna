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
  var context: [String: ContextValue] {
    ["ms": .int(Diagnostics.wholeMilliseconds(elapsed))]
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
      "windowId": .string(String(format: "0x%x", id.windowID)),
      "result": .string(resultWord),
      "ms": .int(Diagnostics.wholeMilliseconds(elapsed)),
    ]
    if let bundle {
      context["bundle"] = .string(bundle)
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
