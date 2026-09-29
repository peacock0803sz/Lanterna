import AppKit
import Foundation

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
    /// while untouched ones take their defaults; emptied actions refill
    /// with their free defaults only once every action in the tier has
    /// claimed, so a refill cannot steal a key a later custom would take.
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
        }
        for action in actions where table.effective[action]?.isEmpty == true {
            table.refill(action)
        }
    }

    /// Validates one action's entries, dropping the bad ones with issues.
    /// An empty result reads as absent, so the tier takes the defaults.
    /// A key spelled twice counts once, silently: repeating oneself is
    /// not a conflict with anyone.
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
        var seen = Set<ResolvedKey>()
        return (kept.filter { seen.insert($0).inserted }, issues)
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
        guard KeyBindingTable.allows(modifiers: flags, mode: mode) else {
            return nil
        }
        return ResolvedKey(keyCode: UInt16(raw.keyCode), modifiers: flags)
    }

    /// The sharing the spec excuses: query clearing and cancelling may
    /// hold the same keys, and the press-time precedence sorts them out.
    static func isExcusedPair(_ first: KeyBindingAction, _ second: KeyBindingAction) -> Bool {
        let pair: Set<KeyBindingAction> = [.clearQuery, .cancel]
        return pair.contains(first) && pair.contains(second) && first != second
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

    /// The `keybindings` object's span in the file text, by brace matching.
    /// Strings are skipped with their escapes throughout, so braces or
    /// quotes inside values cannot move the span, and a value spelling
    /// the section's name cannot stand in for the section itself.
    private static func keybindingsSpan(in text: String) -> Range<String.Index>? {
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\"" {
                let (word, next) = quotedWord(from: index, in: text)
                if word == "keybindings" {
                    return objectSpan(from: next, in: text)
                }
                index = next
            } else {
                index = text.index(after: index)
            }
        }
        return nil
    }

    /// The string opening here and the index past its closing quote. A
    /// backslash swallows the next character, so an escaped quote cannot
    /// end the word early. An unterminated string runs to the text's end.
    private static func quotedWord(from open: String.Index, in text: String) -> (String, String.Index) {
        var word = ""
        var index = text.index(after: open)
        while index < text.endIndex {
            if text[index] == "\\" {
                let escaped = text.index(after: index)
                if escaped < text.endIndex {
                    word.append(text[escaped])
                    index = text.index(after: escaped)
                } else {
                    index = escaped
                }
            } else if text[index] == "\"" {
                return (word, text.index(after: index))
            } else {
                word.append(text[index])
                index = text.index(after: index)
            }
        }
        return (word, index)
    }

    /// The object opening after the given index: the first brace outside
    /// strings opens it and its match closes it. A closing brace before
    /// any opening means malformed text and no span.
    private static func objectSpan(from start: String.Index, in text: String) -> Range<String.Index>? {
        var depth = 0
        var open: String.Index?
        var index = start
        while index < text.endIndex {
            if text[index] == "\"" {
                index = quotedWord(from: index, in: text).1
            } else {
                if text[index] == "{" {
                    if depth == 0 {
                        open = index
                    }
                    depth += 1
                }
                if text[index] == "}" {
                    depth -= 1
                    if depth == 0, let open {
                        return text.index(after: open) ..< index
                    }
                    if depth < 0 {
                        return nil
                    }
                }
                index = text.index(after: index)
            }
        }
        return nil
    }
}

/// One resolution run: who holds what, what gave way, and the table.
///
/// Split out with the resolver when the table file stood at the length
/// limit: the tiers read in `resolve` while the claiming lives here.
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

    /// Fills an emptied action with its defaults minus taken keys. When
    /// nothing is free the action stays unbound rather than taking
    /// somebody else's key, recorded as a conflict saying so: silence
    /// would read as a working default.
    mutating func refill(_ action: KeyBindingAction) {
        let free = KeyBindingTable.defaults[action].filter { key in
            guard let holder = holders[key] else { return true }
            return KeyBindingResolver.isExcusedPair(action, holder)
        }
        effective[action] = free
        for key in free {
            holders[key] = action
        }
        if free.isEmpty {
            issues.append(KeyBindingIssue(
                action: action, reason: .conflict,
                detail: "every default key is taken; stays unbound"
            ))
        }
    }
}
