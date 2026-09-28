import Foundation

/// Narrowing the list on screen by what the user typed, and nothing else.
///
/// A namespace rather than a type with state: matching is a pure function of
/// the query and the list, so every row of the contract below can be held to
/// without a window server, a clock, or a panel. The state the narrowing
/// keeps between keystrokes (the query and what was chosen when it vanished)
/// belongs to `FilterState`, not here.
enum WindowFilter {
    /// The rows matching the query, in the order they arrived.
    ///
    /// Filtering keeps the order; it never sorts, so the MRU order the list
    /// arrived in survives the narrowing. An empty query returns the input
    /// unchanged, judging not one row, which is what keeps the show path
    /// free of measurable work.
    static func matching(_ query: String, against windows: [WindowItem]) -> [WindowItem] {
        matching(query, against: windows, fuzzy: false)
    }

    /// The rows matching the query, in the order they arrived.
    ///
    /// With fuzzy off this is the legacy substring match; with fuzzy on a
    /// subsequence match counts too. A substring always counts as a
    /// subsequence, so fuzzy matching never narrows the legacy result.
    /// An empty query returns the input unchanged either way.
    static func matching(_ query: String, against windows: [WindowItem], fuzzy: Bool) -> [WindowItem] {
        guard !query.isEmpty else { return windows }
        if fuzzy {
            return windows.filter { matchesSubsequence(query: query, target: combinedText(of: $0)) }
        }
        return windows.filter { matches(query: query, target: combinedText(of: $0)) }
    }

    /// The text one row is judged by: app name, one space, window title.
    static func combinedText(of item: WindowItem) -> String {
        item.appName + " " + item.windowTitle
    }

    /// The single judgement, kept small so a later widening (such as romaji
    /// search) only widens this body. Case-insensitive substring match.
    static func matches(query: String, target: String) -> Bool {
        target.range(of: query, options: .caseInsensitive) != nil
    }

    /// Whether the query's characters appear in the target in order, gaps
    /// allowed. Case-insensitive. An empty query answers false; callers
    /// return the whole list without judging.
    static func matchesSubsequence(query: String, target: String) -> Bool {
        !subsequenceRanges(query: query, in: target).isEmpty
    }

    /// The rows ordered for score mode, keeping the input order otherwise.
    ///
    /// Contiguous substring matches come before scattered subsequence
    /// matches; among those, an earlier match start comes first. Ties keep
    /// the order they arrived in (a stable sort through the index), so
    /// equal rows never change places. An empty query changes nothing.
    static func scoreOrdered(_ rows: [WindowItem], query: String) -> [WindowItem] {
        rows.enumerated().map { entry in
            let target = combinedText(of: entry.element)
            return (offset: entry.offset, quality: matchQuality(query: query, target: target), element: entry.element)
        }.sorted { left, right in
            if left.quality != right.quality {
                return left.quality < right.quality
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    /// How one row ranks: contiguous matches before scattered ones, then
    /// by where the match starts. Rows no matcher judges rank last.
    private static func matchQuality(query: String, target: String) -> (contiguous: Int, start: Int) {
        if let first = matchedRanges(query: query, in: target).first {
            return (0, target.distance(from: target.startIndex, to: first.lowerBound))
        }
        if let first = subsequenceRanges(query: query, in: target).first {
            return (1, target.distance(from: target.startIndex, to: first.lowerBound))
        }
        return (2, Int.max)
    }

    /// Where each query character matched, in order, for highlighting.
    ///
    /// Case-insensitive, and empty when the query never appears in order.
    /// Ranges never overlap: searching resumes past each match. An empty
    /// query matches nothing.
    static func subsequenceRanges(query: String, in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var remainder = text.startIndex ..< text.endIndex
        for character in query {
            guard let found = text.range(of: String(character), options: .caseInsensitive, range: remainder) else {
                return []
            }
            ranges.append(found)
            remainder = found.upperBound ..< text.endIndex
        }
        return ranges
    }

    /// Every range where the query occurs in the text, for highlighting.
    ///
    /// Case-insensitive, and every occurrence rather than only the first.
    /// Ranges never overlap: searching resumes past each match. An empty
    /// query matches nothing.
    static func matchedRanges(query: String, in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var remainder = text.startIndex ..< text.endIndex
        while let found = text.range(of: query, options: .caseInsensitive, range: remainder) {
            ranges.append(found)
            remainder = found.upperBound ..< text.endIndex
        }
        return ranges
    }

    /// The rows a romaji query matches through the engine, in order.
    ///
    /// The single-pattern path: one pattern per query decides every row,
    /// so conventional queries keep matching exactly when the engine's
    /// pattern says so (covered by acceptance, not by a first pass). An
    /// empty query returns the input unchanged, like the legacy path.
    static func matching(_ query: String, against windows: [WindowItem], engine: MigemoEngine) -> [WindowItem] {
        guard !query.isEmpty else { return windows }
        return windows.filter { matches(query: query, target: combinedText(of: $0), engine: engine) }
    }

    /// Whether one row matches a romaji query through the engine.
    static func matches(query: String, target: String, engine: MigemoEngine) -> Bool {
        guard !query.isEmpty else { return true }
        return !matchedRanges(query: query, in: target, engine: engine).isEmpty
    }

    /// Every range where a romaji query matches, for highlighting.
    ///
    /// Ranges cover the whole matched span on the target side, whose
    /// length need not equal the query's. A query no pattern can parse
    /// falls back to a literal match and never fails the filter.
    static func matchedRanges(query: String, in text: String, engine: MigemoEngine) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        if let pattern = engine.pattern(for: query) {
            if let ranges = regexRanges(pattern: pattern, in: text) {
                return ranges
            }
            if let literal = regexRanges(pattern: MigemoEngine.escapedLiteral(query), in: text) {
                return literal
            }
        }
        return matchedRanges(query: query, in: text)
    }

    /// The ranges one regular expression matches, or nil when the
    /// pattern itself cannot be read. An empty hit list means no match,
    /// never a broken pattern.
    private static func regexRanges(pattern: String, in text: String) -> [Range<String.Index>]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let full = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: full).compactMap { Range($0.range, in: text) }
    }

    /// Whether the string a keystroke produced joins the query, and as what.
    ///
    /// Judged by content alone, because origin cannot be told apart this far
    /// down: a confirmed string and a directly typed one arrive as the same
    /// characters. One ASCII character joins only when alphanumeric; anything
    /// longer, or holding non-ASCII, is taken verbatim as a confirmed string.
    static func allowedText(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        guard text.count == 1, let scalar = text.unicodeScalars.first, scalar.isASCII else {
            return text
        }
        return isASCIILetterOrDigit(scalar.value) ? text : nil
    }

    /// ASCII alphanumerics, without reaching for Foundation.
    private static func isASCIILetterOrDigit(_ value: UInt32) -> Bool {
        switch value {
        case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A:
            true
        default:
            false
        }
    }
}
