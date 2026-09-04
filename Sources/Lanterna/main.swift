import AppKit
import Darwin

let launchedAt = ContinuousClock.now

let sampleCount: Int?
do {
    sampleCount = try LaunchArguments.sampleCount(from: ProcessInfo.processInfo.arguments)
} catch {
    Diagnostics.writeLine(error.usage)
    exit(EX_USAGE)
}

let application = NSApplication.shared
// Set before the run loop starts, because `finishLaunching` under the default
// `.regular` policy is what puts an icon in the Dock.
application.setActivationPolicy(.accessory)

let delegate = AppDelegate(launchedAt: launchedAt, sampleCount: sampleCount)
application.delegate = delegate
application.run()
