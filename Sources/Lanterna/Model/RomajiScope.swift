/// Which readings the romaji filter matches.
///
/// Mirrors the config file values (`"kana"`, `"kanji"`).
/// An absent key means `kanji`: unless the file says otherwise, the
/// filter matches kana readings and kanji readings alike.
enum RomajiScope: String, Sendable {
  /// Kana readings only, for holding kanji matches back.
  case kanaOnly = "kana"
  /// Kana readings plus kanji readings (the default).
  case kanaKanji = "kanji"

  /// The scope for one run: a present key wins, an absent key means
  /// matching kanji readings as well.
  static func effective(from config: ValidConfiguration) -> RomajiScope {
    config.romajiScope ?? .kanaKanji
  }
}
