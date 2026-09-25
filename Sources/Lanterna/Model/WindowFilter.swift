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
        guard !query.isEmpty else { return windows }
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
