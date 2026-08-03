import AppKit

/// One switchable window as shown in the switcher list.
///
/// Live window enumeration will later replace where these values come from
/// without changing the shape the view layer consumes.
struct WindowItem: Identifiable {
    let id = UUID()
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String
    let icon: NSImage

    /// Hint shown at the left edge of a row. `prefix` yields the whole name when
    /// it is shorter than two characters, which is the intended behaviour.
    var shortcutHint: String {
        appName.prefix(2).lowercased()
    }
}
