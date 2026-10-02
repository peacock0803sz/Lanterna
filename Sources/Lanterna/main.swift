import AppKit
import Darwin
import Logging

// Named first, so the launch's stamp is when the process started rather
// than when its first line went out.
_ = Diagnostics.currentLaunch

// Wired before anything can write: the first diagnostics line below
// already goes through the mirror backend.
Diagnostics.bootstrap()

let cliOptions: LaunchArguments.Options
do {
  cliOptions = try LaunchArguments.parse(ProcessInfo.processInfo.arguments)
} catch {
  Diagnostics.writeLine(LogLine(.error, .launch, "\(error)\n\(LaunchArguments.usage)"))
  exit(EX_USAGE)
}

for flag in cliOptions.retiredFlags {
  Diagnostics.writeLine(LogLine(.warning, .logs, "launch: \(flag) is no longer used and was ignored"))
}

/// Read before the run loop starts, ahead of the panel's advance build, so
/// the read stays off the path with a time budget. A missing file is
/// scaffolded; anything unreadable falls back to defaults with a line saying
/// why. Existing files are never written.
let options: LaunchArguments.Options
let initialValues: SettingsValues
let launchDesired: Bool
let configFileURL: URL?
let lanternaDirectory: URL?
let tableDirectory = MigemoEngine.tableDirectoryURL()
if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
  let (outcome, url) = AppConfiguration.loadOrScaffold(applicationSupport: base)
  configFileURL = url
  lanternaDirectory = url.deletingLastPathComponent()
  let defaults = ValidConfiguration(
    version: AppConfiguration.currentVersion,
    sampleCount: nil,
    stopMonitorEverySeconds: nil
  )
  switch outcome {
  case .loaded(let decoded):
    options = AppConfiguration.effectiveOptions(file: decoded.config, cli: cliOptions)
    initialValues = SettingsValues.effective(from: decoded.config)
    launchDesired = decoded.config.launchAtLogin ?? false
    openSharedMatcher(
      scope: RomajiScope.effective(from: decoded.config),
      lanternaDirectory: url.deletingLastPathComponent()
    )
    if decoded.assumedVersion {
      Diagnostics.writeLine(LogLine(
        .info,
        .config,
        "config loaded (version 1, assumed): \(url.path)",
        context: ["path": .string(url.path)]
      ))
    } else {
      Diagnostics.writeLine(LogLine(
        .info,
        .config,
        "config loaded (version \(decoded.config.version)): \(url.path)",
        context: ["path": .string(url.path)]
      ))
    }
    for issue in decoded.keyBindingIssues {
      Diagnostics.writeLine(LogLine(
        .warning,
        .config,
        issue.diagnosticsLine,
        context: ["path": .string(url.path), "issue": .string(issue.diagnosticsLine)]
      ))
    }
    if let textScaleIssue = decoded.textScaleIssue {
      Diagnostics.writeLine(LogLine(
        .warning,
        .config,
        "\(textScaleIssue): \(url.path)",
        context: ["path": .string(url.path), "issue": .string("\(textScaleIssue)")]
      ))
    }
    for issue in decoded.groupAssignmentIssues {
      Diagnostics.writeLine(LogLine(
        .warning,
        .config,
        "\(issue.diagnosticsLine): \(url.path)",
        context: ["path": .string(url.path), "issue": .string(issue.diagnosticsLine)]
      ))
    }
    for key in decoded.deprecatedKeys {
      Diagnostics.writeLine(LogLine(
        .warning,
        .logs,
        "config: \(key) is no longer used and was ignored",
        context: ["path": .string(url.path)]
      ))
    }

  case .created:
    options = AppConfiguration.effectiveOptions(file: defaults, cli: cliOptions)
    initialValues = SettingsValues.defaults
    launchDesired = defaults.launchAtLogin ?? false
    openSharedMatcher(
      scope: .kanaKanji,
      lanternaDirectory: url.deletingLastPathComponent()
    )
    Diagnostics.writeLine(LogLine(
      .info,
      .config,
      "config not found; created with defaults: \(url.path)",
      context: ["path": .string(url.path)]
    ))

  case .failed(let reason):
    options = AppConfiguration.effectiveOptions(file: defaults, cli: cliOptions)
    initialValues = SettingsValues.defaults
    launchDesired = defaults.launchAtLogin ?? false
    openSharedMatcher(
      scope: .kanaKanji,
      lanternaDirectory: url.deletingLastPathComponent()
    )
    Diagnostics.writeLine(LogLine(
      .error,
      .config,
      "config invalid (\(reason)); using defaults: \(url.path)",
      context: ["path": .string(url.path), "issue": .string("\(reason)")]
    ))
  }
} else {
  options = cliOptions
  initialValues = SettingsValues.defaults
  launchDesired = false
  configFileURL = nil
  lanternaDirectory = nil
  openSharedMatcher(scope: .kanaKanji, lanternaDirectory: nil)
  Diagnostics.writeLine(LogLine(
    .error,
    .config,
    "config invalid (cannot resolve directory); using defaults",
    context: ["issue": .string("cannot resolve directory")]
  ))
}

/// Starts this launch's saved log once the settings are read and before the
/// panel can run, so making the file and trimming old ones stay off the paths
/// with a time budget. The lines written so far reach the file first.
let savedLogs = SavedLogs.live()
savedLogs?.start(saving: initialValues.saveLogsToDisk)

// Brings the login item in line with the saved setting, ahead of the run
// loop and off the path with a time budget. A change or a failure leaves
// one diagnostics line; quiet runs stay silent. Never stops the launch.
if let report = LaunchAtLogin.sync(desired: launchDesired, service: LaunchAtLogin.liveIfBundled()) {
  Diagnostics.writeLine(LogLine(report.level, .launch, report.line))
}

/// Opens the shared matcher for one run, ahead of the run loop.
///
/// The scope comes from the same config the options do; the dictionary
/// lives beside the config file. A rejected dictionary gets one launch
/// line (missing files stay silent); everything else keeps working
/// kana-only through the legacy fallback in the panel paths.
func openSharedMatcher(scope: RomajiScope, lanternaDirectory: URL?) {
  let active = RomajiMatcher.open(
    scope: scope,
    dictionaryDirectory: lanternaDirectory,
    tableDirectory: MigemoEngine.tableDirectoryURL()
  )
  if scope == .kanaKanji, let lanternaDirectory {
    let dictURL = lanternaDirectory.appendingPathComponent("migemo-dict", isDirectory: false)
    if FileManager.default.fileExists(atPath: dictURL.path), !active {
      Diagnostics.writeLine(LogLine(
        .warning,
        .config,
        "dict invalid (unreadable format); matching kana only: \(dictURL.path)",
        context: ["path": .string(dictURL.path), "issue": .string("unreadable format")]
      ))
    }
  }
}

let application = NSApplication.shared
// Set before the run loop starts, because `finishLaunching` under the default
// `.regular` policy is what puts an icon in the Dock.
application.setActivationPolicy(.accessory)

let delegate = AppDelegate(
  options: options,
  configFileURL: configFileURL,
  lanternaDirectory: lanternaDirectory,
  tableDirectory: tableDirectory,
  initialValues: initialValues,
  savedLogs: savedLogs
)
application.delegate = delegate
application.run()
