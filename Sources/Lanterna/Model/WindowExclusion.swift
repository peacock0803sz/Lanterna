import Foundation

/// One exclusion entry as written in the config file.
///
/// Both fields are required and non-empty; anything else is invalid on its
/// own and ignored without touching the other entries.
struct ExclusionEntry: Equatable, Sendable {
    var app: String
    var titlePattern: String
}

/// One compiled exclusion rule for the show path.
///
/// The display-name pattern is compiled at load, so showing never pays
/// for compilation and never meets a pattern it cannot read: unreadable
/// entries never become rules.
struct ExclusionRule: Sendable {
    /// The raw app string, compared case-insensitively against bundle ids.
    let app: String
    /// The app string as a regular expression over display names,
    /// case-sensitive by the convention of patterns.
    let appRegex: NSRegularExpression
    /// The raw title pattern.
    let titlePattern: String
    /// Whether the title pattern asks for an exact match.
    let titleExact: Bool
    /// The title text to compare: the inner text for exact patterns,
    /// the pattern itself otherwise.
    let titleNeedle: String
}

/// The exclusion list between the config file and the list on screen.
///
/// A namespace like `WindowFilter`: compiling reads the file's entries once,
/// and excluding judges rows without state.
enum WindowExclusion {
    /// Compiles the file's entries into rules, counting the invalid ones.
    ///
    /// Invalid entries (empty app, empty title pattern, unreadable display
    /// pattern) are skipped one by one; the count tells the diagnostics line.
    /// An exact title pattern is recognized here, once, by its anchors.
    static func compile(_ entries: [ExclusionEntry]) -> (rules: [ExclusionRule], invalid: Int) {
        var rules: [ExclusionRule] = []
        var invalid = 0
        for entry in entries {
            guard let rule = compile(entry) else {
                invalid += 1
                continue
            }
            rules.append(rule)
        }
        return (rules, invalid)
    }

    /// Whether one app/title pair may stand as a row in the editor.
    ///
    /// The same rule compiling uses, so the editor flags exactly the rows
    /// showing would skip.
    static func isValid(app: String, titlePattern: String) -> Bool {
        !app.isEmpty && !titlePattern.isEmpty && (try? NSRegularExpression(pattern: app)) != nil
    }

    /// Compiles one entry, or nil when the entry is invalid on its own.
    private static func compile(_ entry: ExclusionEntry) -> ExclusionRule? {
        guard !entry.app.isEmpty, !entry.titlePattern.isEmpty else { return nil }
        guard let appRegex = try? NSRegularExpression(pattern: entry.app) else { return nil }
        let (exact, needle) = splitTitlePattern(entry.titlePattern)
        return ExclusionRule(
            app: entry.app,
            appRegex: appRegex,
            titlePattern: entry.titlePattern,
            titleExact: exact,
            titleNeedle: needle
        )
    }

    /// Splits a title pattern into exact or substring matching.
    ///
    /// Only a pattern wearing both anchors asks for an exact match; a lone
    /// anchor is literal text, matched the substring way.
    static func splitTitlePattern(_ pattern: String) -> (exact: Bool, needle: String) {
        guard pattern.count >= 2, pattern.hasPrefix("^"), pattern.hasSuffix("$") else {
            return (false, pattern)
        }
        return (true, String(pattern.dropFirst().dropLast()))
    }

    /// The rows surviving the rules, in the order they arrived.
    ///
    /// Excluding keeps the order; it never sorts, so the relative order
    /// without exclusions survives. No rules returns the input unchanged,
    /// judging not one row, which is what keeps the show path free of
    /// measurable work.
    static func excluding(_ windows: [WindowItem], rules: [ExclusionRule]) -> [WindowItem] {
        guard !rules.isEmpty else { return windows }
        return windows.filter { !isExcluded($0, rules: rules) }
    }

    /// Whether one row leaves the list under any rule.
    static func isExcluded(_ item: WindowItem, rules: [ExclusionRule]) -> Bool {
        rules.contains { matches(item, rule: $0) }
    }

    /// Both halves must match; one half alone excludes nothing.
    private static func matches(_ item: WindowItem, rule: ExclusionRule) -> Bool {
        guard matchesApp(item, rule: rule) else { return false }
        return matchesTitle(item.windowTitle, rule: rule)
    }

    /// A bundle id match (ignoring case) or a display-name pattern match.
    private static func matchesApp(_ item: WindowItem, rule: ExclusionRule) -> Bool {
        if let bundle = item.bundleIdentifier, bundle.lowercased() == rule.app.lowercased() {
            return true
        }
        let range = NSRange(item.appName.startIndex..., in: item.appName)
        return rule.appRegex.firstMatch(in: item.appName, range: range) != nil
    }

    /// An exact match for anchored patterns, a substring match otherwise,
    /// both ignoring case.
    private static func matchesTitle(_ title: String, rule: ExclusionRule) -> Bool {
        if rule.titleExact {
            return title.compare(rule.titleNeedle, options: .caseInsensitive) == .orderedSame
        }
        return title.range(of: rule.titleNeedle, options: .caseInsensitive) != nil
    }
}
