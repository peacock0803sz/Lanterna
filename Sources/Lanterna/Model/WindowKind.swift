import ApplicationServices

/// What kind of window a listed row stands for.
///
/// The value is carried on `WindowItem` for later steps; the switcher draws
/// every kind the same way today.
enum WindowKind: Sendable {
    case standard
    case dialog
    /// A window whose subrole is unknown or unreadable. Listed anyway, because
    /// dropping a window the user can see is worse than showing one they
    /// cannot switch to.
    case undetermined

    /// Classifies one element of an application's window list, or returns `nil`
    /// when the element must not become a row.
    ///
    /// Only positive evidence excludes: a role that reads as something other
    /// than a window (the Finder desktop reports `AXScrollArea`), or a subrole
    /// that names an auxiliary panel. An attribute that cannot be read carries
    /// no evidence and so never excludes on its own.
    static func classify(role: String?, subrole: String?) -> WindowKind? {
        if let role, role != kAXWindowRole {
            return nil
        }
        switch subrole {
        case kAXStandardWindowSubrole:
            return .standard
        case kAXDialogSubrole, kAXSystemDialogSubrole:
            return .dialog
        case kAXFloatingWindowSubrole, kAXSystemFloatingWindowSubrole:
            return nil
        default:
            return .undetermined
        }
    }
}
