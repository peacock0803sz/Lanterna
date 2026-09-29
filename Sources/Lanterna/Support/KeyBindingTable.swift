import AppKit
import Carbon.HIToolbox

/// How one action's keys are validated, and how hard they fight.
///
/// A static attribute of the action, never stored in the file: `global`
/// combinations reach across the system and must keep their modifiers,
/// `guarded` operations would fire while typing without them, and `bare`
/// panel keys work either way.
enum BindingMode: Equatable, Sendable {
    case global
    case guarded
    case bare
}

/// Every action a key can drive, in the config file's words.
///
/// The raw values are the `keybindings` section's keys, so renaming one
/// renames the file format. The mode decides the validation from FR-012.
enum KeyBindingAction: String, CaseIterable, Equatable, Sendable {
    case show
    case showReverse
    case showFilter
    case next
    case previous
    case commit
    case cancel
    case deleteBackward
    case clearQuery
    case closeWindow
    case quitApplication
    case hideApplication
    case minimizeWindow

    var mode: BindingMode {
        switch self {
        case .show, .showReverse, .showFilter:
            .global
        case .closeWindow, .quitApplication, .hideApplication, .minimizeWindow:
            .guarded
        default:
            .bare
        }
    }
}

/// One binding as the config file spells it, before validation.
struct RawKeyBinding: Equatable, Sendable {
    let keyCode: Int
    let modifiers: [String]
}

/// One binding the panel goes by: a physical key and narrowed modifiers.
struct ResolvedKey: Equatable, Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    /// How lines and controls name it: modifiers first, then the key.
    /// Anything but Tab and Space goes down by number, because a
    /// physical position has no layout-independent letter to spell.
    var displayName: String {
        var parts: [String] = []
        if modifiers.contains(.shift) {
            parts.append("Shift")
        }
        if modifiers.contains(.control) {
            parts.append("Ctrl")
        }
        if modifiers.contains(.option) {
            parts.append("Opt")
        }
        if modifiers.contains(.command) {
            parts.append("Cmd")
        }
        switch Int(keyCode) {
        case kVK_Tab:
            parts.append("Tab")
        case kVK_Space:
            parts.append("Space")
        case kVK_Return:
            parts.append("Return")
        case kVK_ANSI_KeypadEnter:
            parts.append("Enter")
        case kVK_Escape:
            parts.append("Esc")
        case kVK_UpArrow:
            parts.append("Up")
        case kVK_DownArrow:
            parts.append("Down")
        case kVK_Delete:
            parts.append("Backspace")
        default:
            parts.append("key \(keyCode)")
        }
        return parts.joined(separator: "+")
    }
}

/// Why one entry did not survive resolution. The text for the diagnostics
/// line is built by the caller, which knows the losing and winning sides.
enum KeyBindingIssueReason: Equatable, Sendable {
    case invalid
    case conflict
}

/// One fallback and its reason, for the diagnostics lines.
struct KeyBindingIssue: Equatable, Sendable {
    let action: KeyBindingAction?
    let reason: KeyBindingIssueReason
    let detail: String

    /// The one launch line per fallback: what gave way, why, and that
    /// the default stands in. Worded here so the shape stays testable
    /// while the writing itself lives with the launch path.
    var diagnosticsLine: String {
        let reasonWord: String
        switch reason {
        case .invalid:
            reasonWord = "invalid"
        case .conflict:
            reasonWord = "conflict"
        }
        return
            "config keybinding (\(action?.rawValue ?? "unknown") \(reasonWord): \(detail)); using default"
    }
}

/// The resolved table: what each action answers to.
///
/// Built once at launch (and again on every settings save) so no press
/// ever pays for validation. Equality is by value, which is what makes
/// the table unit-testable without a window server.
struct KeyBindingTable: Equatable, Sendable {
    var keys: [KeyBindingAction: [ResolvedKey]]

    subscript(_ action: KeyBindingAction) -> [ResolvedKey] {
        keys[action] ?? []
    }

    /// The long-standing behaviour, key for key.
    static var defaults: KeyBindingTable {
        KeyBindingTable(keys: [
            .show: [ResolvedKey(keyCode: UInt16(kVK_Tab), modifiers: .command)],
            .showReverse: [
                ResolvedKey(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift]),
            ],
            .showFilter: [ResolvedKey(keyCode: UInt16(kVK_Space), modifiers: .command)],
            .next: [ResolvedKey(keyCode: UInt16(kVK_DownArrow), modifiers: [])],
            .previous: [ResolvedKey(keyCode: UInt16(kVK_UpArrow), modifiers: [])],
            .commit: [
                ResolvedKey(keyCode: UInt16(kVK_Return), modifiers: []),
                ResolvedKey(keyCode: UInt16(kVK_ANSI_KeypadEnter), modifiers: []),
            ],
            .cancel: [
                ResolvedKey(keyCode: UInt16(kVK_Escape), modifiers: []),
                ResolvedKey(keyCode: UInt16(kVK_ANSI_Period), modifiers: .command),
            ],
            .deleteBackward: [ResolvedKey(keyCode: UInt16(kVK_Delete), modifiers: [])],
            .clearQuery: [ResolvedKey(keyCode: UInt16(kVK_Escape), modifiers: [])],
            .closeWindow: [ResolvedKey(keyCode: UInt16(kVK_ANSI_W), modifiers: .command)],
            .quitApplication: [ResolvedKey(keyCode: UInt16(kVK_ANSI_Q), modifiers: .command)],
            .hideApplication: [ResolvedKey(keyCode: UInt16(kVK_ANSI_H), modifiers: .command)],
            .minimizeWindow: [ResolvedKey(keyCode: UInt16(kVK_ANSI_M), modifiers: .command)],
        ])
    }

    /// Whether these modifiers may drive the mode at all, before any
    /// key is considered. Shared with the settings UI, so an invalid
    /// assignment is refused there rather than falling back here.
    static func allows(modifiers: NSEvent.ModifierFlags, mode: BindingMode) -> Bool {
        switch mode {
        case .global, .guarded:
            modifiers.contains(.command) || modifiers.contains(.control)
                || modifiers.contains(.option)
        case .bare:
            true
        }
    }

    /// Actions already holding this key, except the action itself and
    /// the excused query-clear/cancel sharing.
    func holders(of key: ResolvedKey, except action: KeyBindingAction) -> [KeyBindingAction] {
        KeyBindingAction.allCases.filter { other in
            guard other != action else { return false }
            guard (keys[other] ?? []).contains(key) else { return false }
            return !KeyBindingResolver.isExcusedPair(action, other)
        }
    }

    /// Whether this press drives the action: the key sits on a bound
    /// position with the required modifiers held. A bare binding only
    /// answers a key that types nothing, so a letter keeps narrowing
    /// the list instead of triggering.
    func matches(_ keystroke: PanelKeystroke, action: KeyBindingAction) -> Bool {
        (keys[action] ?? []).contains { key in
            key.keyCode == keystroke.keyCode
                && key.modifiers.isSubset(of: keystroke.modifiers)
                && (!key.modifiers.isEmpty || !typesText(keystroke))
        }
    }

    /// Whether the press would narrow the list rather than drive.
    ///
    /// Read here, where a row means filtering: going by key code keeps
    /// the table independent of the input source, and what the key made
    /// is only asked where filtering is at stake.
    private func typesText(_ keystroke: PanelKeystroke) -> Bool {
        WindowFilter.allowedText(keystroke.characters) != nil
    }
}
