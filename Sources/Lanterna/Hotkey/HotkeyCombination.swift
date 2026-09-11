import Carbon.HIToolbox

/// The key combinations the switcher takes over.
///
/// Carbon constants are read here, but no Carbon function is called, so the
/// whole type is testable. `HotkeyManager` does the registering.
enum HotkeyCombination: Sendable, CaseIterable {
    case forward
    case reverse

    /// Rides along on the `EventHotKeyID` and comes back on every press, which
    /// is how the handler tells the two apart. Non-zero, so a zeroed-out
    /// identifier cannot be mistaken for a real one.
    var id: UInt32 {
        switch self {
        case .forward: 1
        case .reverse: 2
        }
    }

    var keyCode: UInt32 {
        UInt32(kVK_Tab)
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .forward: UInt32(cmdKey)
        case .reverse: UInt32(cmdKey | shiftKey)
        }
    }

    /// How the combination is spelled in the diagnostics lines the manual
    /// acceptance checks grep for.
    var name: String {
        switch self {
        case .forward: "Cmd+Tab"
        case .reverse: "Shift+Cmd+Tab"
        }
    }

    /// Everything that gets registered. Registration is all-or-each: the two
    /// are registered separately and either can fail on its own.
    static var all: [HotkeyCombination] {
        allCases
    }

    /// Turns an identifier read off a press back into the combination it
    /// stands for, or `nil` for an identifier this app never handed out.
    init?(id: UInt32) {
        guard let match = Self.allCases.first(where: { $0.id == id }) else {
            return nil
        }
        self = match
    }
}
