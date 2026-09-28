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
}
