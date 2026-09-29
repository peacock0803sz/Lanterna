import AppKit
import Darwin
import Logging

// Wired before anything can write: the first diagnostics line below
// already goes through the mirror backend.
Diagnostics.bootstrap()

let cliOptions: LaunchArguments.Options
do {
    cliOptions = try LaunchArguments.parse(ProcessInfo.processInfo.arguments)
} catch {
    Diagnostics.writeLine("\(error)\n\(LaunchArguments.usage)", level: .error)
    exit(EX_USAGE)
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
    case let .loaded(decoded):
        options = AppConfiguration.effectiveOptions(file: decoded.config, cli: cliOptions)
        Diagnostics.threshold = options.logLevel ?? .warning
        initialValues = SettingsValues.effective(from: decoded.config)
        launchDesired = decoded.config.launchAtLogin ?? false
        openSharedMatcher(
            scope: RomajiScope.effective(from: decoded.config),
            lanternaDirectory: url.deletingLastPathComponent()
        )
        if decoded.assumedVersion {
            Diagnostics.writeLine("config loaded (version 1, assumed): \(url.path)", level: .info)
        } else {
            Diagnostics.writeLine(
                "config loaded (version \(decoded.config.version)): \(url.path)", level: .info
            )
        }
        for issue in decoded.keyBindingIssues {
            Diagnostics.writeLine(issue.diagnosticsLine, level: .warning)
        }
        if let textScaleIssue = decoded.textScaleIssue {
            Diagnostics.writeLine("\(textScaleIssue): \(url.path)", level: .warning)
        }
    case .created:
        options = AppConfiguration.effectiveOptions(file: defaults, cli: cliOptions)
        Diagnostics.threshold = options.logLevel ?? .warning
        initialValues = SettingsValues.defaults
        launchDesired = defaults.launchAtLogin ?? false
        openSharedMatcher(
            scope: .kanaKanji,
            lanternaDirectory: url.deletingLastPathComponent()
        )
        Diagnostics.writeLine("config not found; created with defaults: \(url.path)", level: .info)
    case let .failed(reason):
        options = AppConfiguration.effectiveOptions(file: defaults, cli: cliOptions)
        Diagnostics.threshold = options.logLevel ?? .warning
        initialValues = SettingsValues.defaults
        launchDesired = defaults.launchAtLogin ?? false
        openSharedMatcher(
            scope: .kanaKanji,
            lanternaDirectory: url.deletingLastPathComponent()
        )
        Diagnostics.writeLine("config invalid (\(reason)); using defaults: \(url.path)", level: .error)
    }
} else {
    options = cliOptions
    Diagnostics.threshold = options.logLevel ?? .warning
    initialValues = SettingsValues.defaults
    launchDesired = false
    configFileURL = nil
    lanternaDirectory = nil
    openSharedMatcher(scope: .kanaKanji, lanternaDirectory: nil)
    Diagnostics.writeLine("config invalid (cannot resolve directory); using defaults", level: .error)
}

// Brings the login item in line with the saved setting, ahead of the run
// loop and off the path with a time budget. A change or a failure leaves
// one diagnostics line; quiet runs stay silent. Never stops the launch.
if let report = LaunchAtLogin.sync(desired: launchDesired, service: LaunchAtLogin.liveIfBundled()) {
    Diagnostics.writeLine(report.line, level: report.level)
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
            Diagnostics.writeLine(
                "dict invalid (unreadable format); matching kana only: \(dictURL.path)",
                level: .warning
            )
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
    initialValues: initialValues
)
application.delegate = delegate
application.run()
