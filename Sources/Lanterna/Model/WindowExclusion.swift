import Foundation

/// One exclusion entry as written in the config file.
///
/// Both fields are required and non-empty; anything else is invalid on its
/// own and ignored without touching the other entries.
struct ExclusionEntry: Hashable, Sendable {
    var app: String
    var titlePattern: String
}

/// One compiled exclusion rule for the show path.
///
/// The display-name pattern is compiled at load, so showing never pays
/// for compilation and never meets a pattern it cannot read: unreadable
/// entries never become rules. Case-insensitive halves are folded at
/// load, so showing compares bytes instead of folding every row.
struct ExclusionRule: Sendable {
    /// The raw app string, compared case-insensitively against bundle ids.
    let app: String
    /// The app string folded for the bundle comparison.
    let appFolded: String
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
    /// The needle folded for the case-insensitive comparison.
    let needleFolded: String
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
            appFolded: entry.app.lowercased(),
            appRegex: appRegex,
            titlePattern: entry.titlePattern,
            titleExact: exact,
            titleNeedle: needle,
            needleFolded: needle.lowercased()
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

    /// Whether one row leaves the list under any rule. The row's compared
    /// halves are folded once here, so a rule never folds what another
    /// rule already folded.
    static func isExcluded(_ item: WindowItem, rules: [ExclusionRule]) -> Bool {
        let bundle = item.bundleIdentifier?.lowercased()
        let title = item.windowTitle.lowercased()
        return rules.contains { matches(bundle: bundle, title: title, appName: item.appName, rule: $0) }
    }

    /// Both halves must match; one half alone excludes nothing. The title
    /// is judged first because a folded equality or substring check costs
    /// far less than a regular-expression pass, so rows matching nothing
    /// usually pay nothing per rule beyond it.
    private static func matches(bundle: String?, title: String, appName: String, rule: ExclusionRule) -> Bool {
        guard matchesTitle(title, rule: rule) else { return false }
        if bundle == rule.appFolded {
            return true
        }
        let range = NSRange(appName.startIndex..., in: appName)
        return rule.appRegex.firstMatch(in: appName, range: range) != nil
    }

    /// An exact match for anchored patterns, a substring match otherwise,
    /// over already-folded text.
    private static func matchesTitle(_ title: String, rule: ExclusionRule) -> Bool {
        if rule.titleExact {
            return title == rule.needleFolded
        }
        return title.range(of: rule.needleFolded) != nil
    }
}
