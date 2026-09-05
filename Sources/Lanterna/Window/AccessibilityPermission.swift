import ApplicationServices

/// Whether this process may read other applications' windows.
///
/// Stateless: the system owns the answer, and it can change while the app runs
/// because the user grants it in System Settings.
@MainActor
enum AccessibilityPermission {
    /// Asks the system, optionally letting it show its own dialog.
    ///
    /// The prompt is the system's, shown at most once per launch, because a
    /// home-grown explanation would be one more thing to keep in step with the
    /// settings pane it points at.
    static func isTrusted(promptingIfNeeded: Bool) -> Bool {
        let options = [promptOptionKey: promptingIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// `kAXTrustedCheckOptionPrompt` is imported as a mutable C global, which
    /// Swift 6 rejects as shared mutable state, so its documented value is
    /// written out. Named here rather than inline so there is one copy of it.
    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"
}
