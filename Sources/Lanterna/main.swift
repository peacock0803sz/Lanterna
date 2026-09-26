import AppKit
import Darwin

let cliOptions: LaunchArguments.Options
do {
    cliOptions = try LaunchArguments.parse(ProcessInfo.processInfo.arguments)
} catch {
    Diagnostics.writeLine("\(error)\n\(LaunchArguments.usage)")
    exit(EX_USAGE)
}

/// Read before the run loop starts, ahead of the panel's advance build, so
/// the read stays off the path with a time budget. A missing file is
/// scaffolded; anything unreadable falls back to defaults with a line saying
/// why. Existing files are never written.
let options: LaunchArguments.Options
if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
    let (outcome, url) = AppConfiguration.loadOrScaffold(applicationSupport: base)
    let defaults = ValidConfiguration(
        version: AppConfiguration.currentVersion,
        sampleCount: nil,
        stopMonitorEverySeconds: nil
    )
    switch outcome {
    case let .loaded(decoded):
        options = AppConfiguration.effectiveOptions(file: decoded.config, cli: cliOptions)
        if decoded.assumedVersion {
            Diagnostics.writeLine("config loaded (version 1, assumed): \(url.path)")
        } else {
            Diagnostics.writeLine("config loaded (version \(decoded.config.version)): \(url.path)")
        }
    case .created:
        options = AppConfiguration.effectiveOptions(file: defaults, cli: cliOptions)
        Diagnostics.writeLine("config not found; created with defaults: \(url.path)")
    case let .failed(reason):
        options = AppConfiguration.effectiveOptions(file: defaults, cli: cliOptions)
        Diagnostics.writeLine("config invalid (\(reason)); using defaults: \(url.path)")
    }
} else {
    options = cliOptions
    Diagnostics.writeLine("config invalid (cannot resolve directory); using defaults")
}

let application = NSApplication.shared
// Set before the run loop starts, because `finishLaunching` under the default
// `.regular` policy is what puts an icon in the Dock.
application.setActivationPolicy(.accessory)

let delegate = AppDelegate(options: options)
application.delegate = delegate
application.run()
