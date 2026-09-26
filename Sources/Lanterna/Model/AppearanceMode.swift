import AppKit

/// Which appearance the panel and the guide windows use.
///
/// Mirrors the config file values (`"system"`, `"light"`, `"dark"`).
/// Absent keys mean `system`, the long-standing behaviour of following
/// the system appearance. Kept apart from `DisplayMode`: that one decides
/// where rows go, this one only how the windows look.
enum AppearanceMode: String, Sendable {
    /// Follow the system appearance, whatever it currently is.
    case system
    /// Stay light whatever the system says.
    case light
    /// Stay dark whatever the system says.
    case dark

    /// The mode for one run: a present key wins, an absent key means
    /// following the system.
    static func effective(from config: ValidConfiguration) -> AppearanceMode {
        config.appearanceMode ?? .system
    }

    /// The look a window is given. `nil` leaves the window following the
    /// system, which is what `system` means.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
