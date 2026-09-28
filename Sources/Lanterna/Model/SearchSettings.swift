/// The three search-quality settings as one value.
///
/// The settings travel together everywhere — options, presenter, key
/// commands, filter, panel, views — so one copy replaces three records
/// of one thing. The file and the settings UI keep the keys apart;
/// this joins them where they are used.
struct SearchSettings: Equatable, Sendable {
    /// Whether subsequence queries match as well as substrings.
    var fuzzyMatchEnabled = true
    /// How many query characters (`Character`) the shortcut memory covers.
    /// Longer queries are neither recorded nor applied. 0 means off.
    var shortcutMemoryLength = 5
    /// The order narrowed rows draw in.
    var ordering: SearchOrdering = .mru

    /// The settings for one run: present keys win, absent keys mean
    /// the defaults.
    static func effective(from config: ValidConfiguration) -> SearchSettings {
        SearchSettings(
            fuzzyMatchEnabled: config.fuzzyMatchEnabled ?? true,
            shortcutMemoryLength: config.shortcutMemoryLength ?? 5,
            ordering: SearchOrdering.effective(from: config)
        )
    }
}
