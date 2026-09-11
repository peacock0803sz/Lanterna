import CoreGraphics
import PrivateAPIs

/// The window server's own Cmd+Tab and Shift+Cmd+Tab.
///
/// Registering an application hotkey is only half of taking a combination
/// over. While the system still holds it, the Dock and the window server
/// consume the press before any application sees it, so the other half is
/// turning the system's assignment off. The two combinations are switched
/// together: leaving Shift+Cmd+Tab alone would keep the system's reverse
/// switcher answering a key this app believes it owns.
@MainActor
enum SystemSwitcherShortcuts {
    /// A shortcut that would not change, and what the window server said about
    /// it. Worth reporting rather than dropping: the visible symptom is the
    /// system's switcher appearing over one this app thinks it is showing.
    struct Failure: Sendable, CustomStringConvertible {
        let combination: HotkeyCombination
        let status: CGError

        var description: String {
            "\(combination.name) (error \(status.rawValue))"
        }
    }

    /// Stops the system answering either combination. Returns the ones that
    /// would not change; empty is the ordinary case.
    static func disable() -> [Failure] {
        write(isEnabled: false)
    }

    /// Gives both back to the system.
    ///
    /// Always writes "enabled" rather than putting back whatever was found
    /// earlier. A run that was killed leaves them off, and a later run that
    /// read that state back would take it for the user's own preference and
    /// never turn them on again. On is the system default, and nothing but
    /// this app has a reason to turn them off.
    static func restore() -> [Failure] {
        write(isEnabled: true)
    }

    /// What to write when some of them would not go off. `nil` when they all
    /// did.
    static func summaryLine(disabling failures: [Failure]) -> String? {
        summaryLine(verb: "disable", failures)
    }

    /// What to write when some of them would not go back on.
    static func summaryLine(restoring failures: [Failure]) -> String? {
        summaryLine(verb: "restore", failures)
    }

    private static func summaryLine(verb: String, _ failures: [Failure]) -> String? {
        guard !failures.isEmpty else {
            return nil
        }
        return "could not \(verb) the system's "
            + failures.map(\.description).joined(separator: ", ")
    }

    private static func write(isEnabled: Bool) -> [Failure] {
        HotkeyCombination.all.compactMap { combination in
            let status = CGSSetSymbolicHotKeyEnabled(symbolicHotKey(for: combination), isEnabled)
            guard status != .success else {
                return nil
            }
            return Failure(combination: combination, status: status)
        }
    }

    /// Which of the window server's shortcuts each combination stands for.
    /// The two sets of identifiers are unrelated numbering spaces that happen
    /// to agree, so the correspondence is spelled out rather than assumed.
    private static func symbolicHotKey(for combination: HotkeyCombination) -> CGSSymbolicHotKey {
        switch combination {
        case .forward: CGSSymbolicHotKey(kCGSHotKeyCommandTab)
        case .reverse: CGSSymbolicHotKey(kCGSHotKeyCommandShiftTab)
        }
    }
}
