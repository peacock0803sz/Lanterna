/// Which rows row numbers cover.
///
/// Mirrors the config file values (`"windows"`, `"allRows"`).
/// An absent key means `windows`: unless the file says otherwise, only
/// window rows take numbers.
enum NumberScope: String, Sendable {
  /// Only rows naming a window take numbers.
  case windows
  /// Every row takes numbers, including rows naming a running
  /// application with no window. Headings and empty lines never do.
  case allRows

  /// The scope for one run: a present key wins, an absent key means
  /// window rows alone.
  static func effective(from config: ValidConfiguration) -> NumberScope {
    config.numberScope ?? .windows
  }
}
