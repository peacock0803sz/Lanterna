/// How the left edge of each row reads.
///
/// Mirrors the config file values (`"prefix"`, `"numbers"`, `"neither"`).
/// An absent key means `prefix`: unless the file says otherwise, rows
/// keep their shortcut hints.
enum HintsMode: String, Sendable {
  /// The application shortcut hint, as before.
  case prefix
  /// The row numbers, always shown.
  case numbers
  /// No hint frame at all.
  case neither

  /// The mode for one run: a present key wins, an absent key means
  /// prefix hints.
  static func effective(from config: ValidConfiguration) -> HintsMode {
    config.hintsMode ?? .prefix
  }
}
