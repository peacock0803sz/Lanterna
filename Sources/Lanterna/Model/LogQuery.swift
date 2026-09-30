import Foundation

/// What the query row holds: either a lightweight filter string or a
/// read-only database statement. The two never mix; switching rows
/// drops the conditions rather than converting them.
///
/// The lightweight row stays the default with its guide beside it.
/// The database row is the escape hatch for conditions the compact
/// syntax cannot say.
struct LogQuery: Equatable, Sendable {
  /// Which syntax the row speaks.
  enum Mode: Equatable, Sendable {
    case lightweight
    case database
  }

  /// Starts a fresh row: lightweight, empty, default time window.
  static var fresh: LogQuery {
    LogQuery()
  }

  /// The active syntax.
  var mode = Mode.lightweight
  /// The filter string. Source of truth while in lightweight mode.
  var lightweightText = ""
  /// The statement text. Source of truth while in database mode.
  var databaseText = ""

  /// The conditions currently in force: the row text of the active
  /// mode, or nothing when the row is empty.
  var activeText: String {
    switch mode {
    case .lightweight: lightweightText
    case .database: databaseText
    }
  }
}
