import Logging

/// The four words users may write, read onto swift-log's levels.
///
/// swift-log knows seven levels; this feature admits four of them
/// (`error`, `warning`, `info`, `debug`). The words match swift-log's
/// names outright, so there is no table to drift: anything else,
/// including `warn`, refuses the way out-of-range numbers do.
extension Logger.Level {
  /// Reads one word exactly as written. Only the four lowercase words
  /// count.
  static func parse(word: String) -> Logger.Level? {
    switch word {
    case "error": .error
    case "warning": .warning
    case "info": .info
    case "debug": .debug
    default: nil
    }
  }
}
