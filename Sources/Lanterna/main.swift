import AppKit
import Darwin

let options: LaunchArguments.Options
do {
    options = try LaunchArguments.parse(ProcessInfo.processInfo.arguments)
} catch {
    Diagnostics.writeLine("\(error)\n\(LaunchArguments.usage)")
    exit(EX_USAGE)
}

let application = NSApplication.shared
// Set before the run loop starts, because `finishLaunching` under the default
// `.regular` policy is what puts an icon in the Dock.
application.setActivationPolicy(.accessory)

let delegate = AppDelegate(sampleCount: options.sampleCount)
application.delegate = delegate
application.run()
