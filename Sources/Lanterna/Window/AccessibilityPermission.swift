import ApplicationServices

/// Whether this process may read other applications' windows.
///
/// Stateless: the system owns the answer, and it can change while the app runs
/// because the user grants it in System Settings.
@MainActor
enum AccessibilityPermission {
    /// Asks the system, optionally letting it show its own dialog.
    ///
    /// The prompt is the system's because a home-grown explanation would be one
    /// more thing to keep in step with the settings pane it points at. Nothing
    /// here limits how often it is shown; asking once per launch is the
    /// caller's rule (`AppDelegate.windowsToShow()`).
    static func isTrusted(promptingIfNeeded: Bool) -> Bool {
        let options = [promptOptionKey: promptingIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// `kAXTrustedCheckOptionPrompt` is imported as a mutable C global, which
    /// Swift 6 rejects as shared mutable state, so the string it resolves to is
    /// written out (checked against the SDK). Named here rather than inline so
    /// there is one copy of it.
    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"
}
