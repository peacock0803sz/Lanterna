import AppKit

let launchedAt = ContinuousClock.now

let application = NSApplication.shared
// Set before the run loop starts so no window is ever created under the default
// policy, which would put an icon in the Dock.
application.setActivationPolicy(.accessory)

let delegate = AppDelegate(launchedAt: launchedAt)
application.delegate = delegate
application.run()
