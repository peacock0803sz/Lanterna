/// Which order the narrowed rows draw in.
///
/// Mirrors the config file values (`"mru"`, `"score"`).
/// An absent key means `mru`: unless the file says otherwise, rows stay
/// in the order they arrived in, with only the remembered row ahead.
enum SearchOrdering: String, Sendable {
  /// Recent use first; the remembered row alone comes ahead.
  case mru
  /// Best match first: contiguous matches, then earlier match starts,
  /// with ties in the order they arrived in.
  case score

  /// The ordering for one run: a present key wins, an absent key means
  /// recent use first.
  static func effective(from config: ValidConfiguration) -> SearchOrdering {
    SearchOrdering(rawValue: config.resultOrder ?? "mru") ?? .mru
  }
}
