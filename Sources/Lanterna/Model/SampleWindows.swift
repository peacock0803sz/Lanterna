import AppKit

/// Static stand-in for the live window list.
///
/// The entries deliberately cover the display cases the layout has to survive:
/// two windows of one application, a title and an application name long enough
/// to truncate, an application that is not installed, and enough rows to exceed
/// the panel's maximum height.
///
/// Reached only through `--sample-count`; the default path lists live windows.
@MainActor
enum SampleWindows {
    private struct Template {
        let appName: String
        let bundleIdentifier: String
        let windowTitle: String
    }

    /// Window ids are synthesised from a base far above any id the window
    /// server hands out, so a fixture row can never collide with a live one.
    private static let fixtureWindowIDBase: CGWindowID = 1_000_000_000

    static func standard() -> [WindowItem] {
        templates.enumerated().map { index, template in
            item(from: template, index: index)
        }
    }

    /// Builds exactly `count` entries for verifying how the panel reacts to list
    /// length. Templates are cycled, but the index keeps every entry's id
    /// distinct — duplicate ids would make list rendering and selection
    /// undefined.
    ///
    /// The count is validated where it enters the process (`LaunchArguments`),
    /// so a negative value reaching here is a programming error.
    static func make(count: Int) -> [WindowItem] {
        precondition(count >= 0, "count must not be negative")
        return (0 ..< count).map { item(from: templates[$0 % templates.count], index: $0) }
    }

    private static func item(from template: Template, index: Int) -> WindowItem {
        WindowItem(
            id: WindowItem.Identifier(windowID: fixtureWindowIDBase + CGWindowID(index)),
            ownerProcessIdentifier: 0,
            appName: template.appName,
            bundleIdentifier: template.bundleIdentifier,
            windowTitle: template.windowTitle,
            kind: .standard,
            isMinimized: false,
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
