import AppKit

/// Static stand-in for the live window list.
///
/// The entries deliberately cover the display cases the layout has to survive:
/// two windows of one application, a title and an application name long enough
/// to truncate, an application that is not installed, and enough rows to exceed
/// the panel's maximum height.
@MainActor
enum SampleWindows {
    private struct Template {
        let appName: String
        let bundleIdentifier: String
        let windowTitle: String
    }

    static func standard() -> [WindowItem] {
        templates.map(item(from:))
    }

    /// Builds exactly `count` entries for verifying how the panel reacts to list
    /// length. Templates are cycled, but every entry gets a fresh identity —
    /// duplicate ids would make list rendering and selection undefined.
    static func make(count: Int) -> [WindowItem] {
        guard count > 0 else { return [] }
        return (0 ..< count).map { item(from: templates[$0 % templates.count]) }
    }

    private static func item(from template: Template) -> WindowItem {
        WindowItem(
            id: WindowItem.Identifier(),
            appName: template.appName,
            bundleIdentifier: template.bundleIdentifier,
            windowTitle: template.windowTitle,
            icon: AppIconResolver.icon(forBundleIdentifier: template.bundleIdentifier)
        )
    }

    private static let templates: [Template] = [
        Template(
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Lanterna — a list-style window switcher for macOS"
        ),
        Template(
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Quarterly planning document with a deliberately long window title "
                + "kept here to prove that titles truncate instead of wrapping"
        ),
        Template(
            appName: "Finder",
            bundleIdentifier: "com.apple.finder",
            windowTitle: "Lanterna"
        ),
        Template(
            appName: "Finder",
            bundleIdentifier: "com.apple.finder",
            windowTitle: "Downloads"
        ),
        Template(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "peacock — swift build"
        ),
        Template(
            appName: "Mail",
            bundleIdentifier: "com.apple.mail",
            windowTitle: "Inbox — 3 unread"
        ),
        Template(
            appName: "Calendar",
            bundleIdentifier: "com.apple.iCal",
            windowTitle: "July 2026"
        ),
        Template(
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Switcher design notes"
        ),
        Template(
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "constitution.pdf"
        ),
        Template(
            appName: "Music",
            bundleIdentifier: "com.apple.Music",
            windowTitle: "Library"
        ),
        Template(
            appName: "System Settings",
            bundleIdentifier: "com.apple.systempreferences",
            windowTitle: "Privacy & Security"
        ),
        Template(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "peacock0803sz/Lanterna — GitHub"
        ),
        Template(
            appName: "Discord",
            bundleIdentifier: "com.hnc.Discord",
            windowTitle: "#general"
        ),
        Template(
            appName: "1Password",
            bundleIdentifier: "com.1password.1password",
            windowTitle: "All Vaults"
        ),
        Template(
            appName: "Keynote",
            bundleIdentifier: "com.apple.iWork.Keynote",
            windowTitle: "Lanterna walkthrough"
        ),
        Template(
            appName: "Karabiner-EventViewer",
            bundleIdentifier: "org.pqrs.Karabiner-EventViewer",
            windowTitle: "Event Viewer"
        ),
        Template(
            appName: "Uninstalled Example",
            bundleIdentifier: "com.example.lanterna.uninstalled",
            windowTitle: "Placeholder icon row"
        ),
    ]
}
