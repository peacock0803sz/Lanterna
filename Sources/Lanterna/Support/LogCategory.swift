/// Which part of the app a diagnostics line came from.
///
/// Required on every line, so a line without one fails to compile rather
/// than landing unsorted. A line whose part is unclear takes the role of
/// the file that emits it.
enum LogCategory: String, CaseIterable, Sendable {
  /// Startup and shutdown: the launch summary, sample counts, termination.
  case launch
  /// Reading and saving the settings file.
  case config
  /// The global hotkey and the event tap behind it.
  case hotkey
  /// The modifier-key monitor and its periodic stop.
  case modifier
  /// Showing and hiding the switcher panel, with its measurements.
  case panel
  /// Gathering the window list.
  case enumerate
  /// Applying the exclusion rules to the list.
  case filter
  /// The outcome of switching to a window, timeouts included.
  case activate
  /// Space changes.
  case space
  /// The diagnostics log itself: write failures, skipped lines, retired
  /// settings and flags.
  case logs
}
