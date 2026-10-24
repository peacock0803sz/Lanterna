import AppKit

// MARK: - ReopenableApplication

/// What reopening asks of an application.
///
/// Behind a protocol for the reason quitting hides behind one: a test
/// process wants to script the answers, and no live application can be
/// asked to lack a bundle on demand. The real application answers below.
protocol ReopenableApplication: Sendable {
  var bundleURL: URL? { get }
  var localizedName: String? { get }
  var executableURL: URL? { get }
  var bundleIdentifier: String? { get }
}

// MARK: - NSRunningApplication + ReopenableApplication

extension NSRunningApplication: ReopenableApplication { }

// MARK: - ApplicationReopener

/// Reopens a windowless application the way its Dock icon does.
///
/// The workspace sends the application the reopen signal; what the
/// application makes of it — a new window, unhiding, nothing — is the
/// application's own doing, so nothing here waits or checks. The signal
/// goes out by opening the application through `NSWorkspace` rather than
/// as an Apple event sent from this process.
///
/// The late answer is a line of its own rather than part of the take's
/// note: the take returns once the signal is sent, and the answer may
/// arrive after the pair is already written.
struct ApplicationReopener: Sendable {

  // MARK: Lifecycle

  /// The defaults talk to the real workspace. Tests replace them with a
  /// script, so no suite opens a real window.
  init(
    findApplication: @escaping @Sendable (pid_t) -> (any ReopenableApplication)? = {
      NSRunningApplication(processIdentifier: $0)
    },
    openApplication: @escaping @Sendable (
      URL,
      NSWorkspace.OpenConfiguration,
      (@Sendable (Error?) -> Void)?
    ) -> Void = { url, configuration, completion in
      NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
        completion?(error)
      }
    },
    writeLine: @escaping @Sendable (LogLine) -> Void = { Diagnostics.writeLine($0) }
  ) {
    self.findApplication = findApplication
    self.openApplication = openApplication
    self.writeLine = writeLine
  }

  // MARK: Internal

  /// Sends the reopen signal, returning what the take notes. A late
  /// failure writes its own line carrying who it was.
  func reopen(processIdentifier: pid_t) -> ReopenNote {
    guard
      let application = findApplication(processIdentifier),
      let bundleURL = application.bundleURL
    else {
      return .skippedNoBundle
    }
    let name = RunningApplicationInfo.displayName(
      localizedName: application.localizedName,
      bundleURL: application.bundleURL,
      executableURL: application.executableURL,
      processIdentifier: processIdentifier
    )
    let bundle = application.bundleIdentifier
    openApplication(bundleURL, Self.configuration) { [writeLine] error in
      // Off the main thread, so nothing but the line happens here.
      guard let error else { return }
      let reason = PanelExitMeasurement.oneLine(error.localizedDescription, fallback: "unknown")
      var context: [String: ContextValue] = [
        "pid": .int(Int(processIdentifier))
      ]
      if let bundle {
        context["bundle"] = .string(bundle)
      }
      writeLine(LogLine(
        .notice,
        .activate,
        "reopen of \(PanelExitMeasurement.oneLine(name, fallback: "unknown")) failed (\(reason))",
        context: context
      ))
    }
    return .requested
  }

  // MARK: Private

  /// The signal goes to the running application itself: no new instance,
  /// no recent item, brought forward.
  private static var configuration: NSWorkspace.OpenConfiguration {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = false
    configuration.addsToRecentItems = false
    return configuration
  }

  private let findApplication: @Sendable (pid_t) -> (any ReopenableApplication)?
  private let openApplication: @Sendable (
    URL,
    NSWorkspace.OpenConfiguration,
    (@Sendable (Error?) -> Void)?
  ) -> Void
  private let writeLine: @Sendable (LogLine) -> Void

}
