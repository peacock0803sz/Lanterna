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
}

/// Turns the file's words into the table the panel goes by.
///
/// Priority runs in tiers: customized globals in file order, then
/// untouched global defaults, then customized panel actions in file
/// order, then untouched panel defaults. A customized key always beats
/// an untouched default except across the invocation line: the panel
/// side gives way, because losing the invocation leaves no way back in
/// while losing an operation only degrades one gesture.
enum KeyBindingResolver {
    /// Resolves one section. Actions absent from `section` keep their
    /// defaults; `order` carries the file's declaration order, which
    /// decides ties among customized actions.
    static func resolve(
        _ section: [KeyBindingAction: [RawKeyBinding]],
        order: [KeyBindingAction]
    ) -> (KeyBindingTable, [KeyBindingIssue]) {
        var table = ClaimTable()
        let customs = order.filter { !(section[$0] ?? []).isEmpty }
        let untouched = KeyBindingAction.allCases.filter { !customs.contains($0) }
        claimTier(customs.filter { $0.mode == .global }, from: section, table: &table)
        claimTier(untouched.filter { $0.mode == .global }, from: nil, table: &table)
        claimTier(customs.filter { $0.mode != .global }, from: section, table: &table)
        claimTier(untouched.filter { $0.mode != .global }, from: nil, table: &table)
        return (KeyBindingTable(keys: table.effective), table.issues)
    }

    /// Claims one tier in order. Customized actions resolve their entries
    /// while untouched ones take their defaults; an action left empty
    /// refills with its free defaults.
    private static func claimTier(
        _ actions: [KeyBindingAction],
        from section: [KeyBindingAction: [RawKeyBinding]]?,
        table: inout ClaimTable
    ) {
        for action in actions {
            if let section {
                let (keys, entryIssues) = validated(action, in: section)
                table.issues += entryIssues
                table.claim(action, keys)
            } else {
                table.claim(action, KeyBindingTable.defaults[action])
            }
            if table.effective[action]?.isEmpty == true {
                table.refill(action)
            }
        }
    }

    /// Validates one action's entries, dropping the bad ones with issues.
    /// An empty result reads as absent, so the tier takes the defaults.
    private static func validated(
        _ action: KeyBindingAction,
        in section: [KeyBindingAction: [RawKeyBinding]]
    ) -> ([ResolvedKey], [KeyBindingIssue]) {
        guard let raws = section[action], !raws.isEmpty else { return ([], []) }
        var kept: [ResolvedKey] = []
        var issues: [KeyBindingIssue] = []
        for raw in raws {
            guard let resolved = validatedEntry(raw, mode: action.mode) else {
                issues.append(KeyBindingIssue(
                    action: action, reason: .invalid,
                    detail: "keyCode \(raw.keyCode) modifiers \(raw.modifiers.joined(separator: "+"))"
                ))
                continue
            }
            kept.append(resolved)
        }
        return (kept, issues)
    }

    /// One resolution run: who holds what, what gave way, and the table.
    ///
    /// Split out when `resolve` stood at the length limit: the tiers read
    /// in `resolve` while the claiming lives here.
    private struct ClaimTable {
        var holders: [ResolvedKey: KeyBindingAction] = [:]
        var issues: [KeyBindingIssue] = []
        var effective: [KeyBindingAction: [ResolvedKey]] = [:]

        /// Claims keys for one action. A key already held by another action
        /// is dropped with a conflict, unless the pair is the excused
        /// query-clear/cancel sharing.
        mutating func claim(_ action: KeyBindingAction, _ candidates: [ResolvedKey]) {
            var kept: [ResolvedKey] = []
            for key in candidates {
                if let holder = holders[key], holder != action {
                    if KeyBindingResolver.isExcusedPair(action, holder) {
                        kept.append(key)
                        continue
                    }
                    issues.append(KeyBindingIssue(
                        action: action, reason: .conflict,
                        detail: "keyCode \(key.keyCode) is already taken"
                    ))
                    continue
                }
                kept.append(key)
                holders[key] = action
            }
            effective[action] = kept
        }

        /// Fills an emptied action with its defaults minus taken keys.
        /// No issue: the loss that led here was already recorded, and an
        /// action left with nothing simply stays unbound rather than
        /// taking somebody else's key.
        mutating func refill(_ action: KeyBindingAction) {
            let free = KeyBindingTable.defaults[action].filter { key in
                guard let holder = holders[key] else { return true }
                return KeyBindingResolver.isExcusedPair(action, holder)
            }
            effective[action] = free
            for key in free {
                holders[key] = action
            }
        }
    }

    /// The file's declaration order for the section's actions.
    ///
    /// JSON objects carry no order, so this walks the file text: from the
    /// `keybindings` key to its closing brace, recording each action word's
    /// first offset. Anything outside that span is somebody else's key with
    /// the same spelling and is ignored.
    static func declarationOrder(in text: String) -> [KeyBindingAction] {
        guard let sectionRange = keybindingsSpan(in: text) else { return [] }
        let body = String(text[sectionRange])
        var hits: [(Int, KeyBindingAction)] = []
        for action in KeyBindingAction.allCases {
            let needle = "\"\(action.rawValue)\""
            if let range = body.range(of: needle) {
                hits.append((body.distance(from: body.startIndex, to: range.lowerBound), action))
            }
        }
        return hits.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// One entry against its mode. `nil` means dropped.
    private static func validatedEntry(_ raw: RawKeyBinding, mode: BindingMode) -> ResolvedKey? {
        guard raw.keyCode >= 0, raw.keyCode <= Int(UInt16.max) else { return nil }
        var flags = NSEvent.ModifierFlags()
        for word in raw.modifiers {
            switch word {
            case "cmd": flags.insert(.command)
            case "ctrl": flags.insert(.control)
            case "opt": flags.insert(.option)
            case "shift": flags.insert(.shift)
            default: return nil
            }
        }
        switch mode {
        case .global, .guarded:
            guard flags.contains(.command) || flags.contains(.control)
                || flags.contains(.option)
            else {
                return nil
            }
        case .bare:
            break
        }
        return ResolvedKey(keyCode: UInt16(raw.keyCode), modifiers: flags)
    }

    /// The sharing the spec excuses: query clearing and cancelling may
    /// hold the same keys, and the press-time precedence sorts them out.
    static func isExcusedPair(_ first: KeyBindingAction, _ second: KeyBindingAction) -> Bool {
        let pair: Set<KeyBindingAction> = [.clearQuery, .cancel]
        return pair.contains(first) && pair.contains(second) && first != second
    }

    /// The `keybindings` object's span in the file text, by brace matching.
    private static func keybindingsSpan(in text: String) -> Range<String.Index>? {
        guard let keyRange = text.range(of: "\"keybindings\""),
              let open = text[keyRange.upperBound...].firstIndex(of: "{")
        else {
            return nil
        }
        var depth = 0
        var index = open
        while index < text.endIndex {
            if text[index] == "{" {
                depth += 1
            }
            if text[index] == "}" {
                depth -= 1
                if depth == 0 {
                    let afterOpen = text.index(after: open)
                    return afterOpen ..< index
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
