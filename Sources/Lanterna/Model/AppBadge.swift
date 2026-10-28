import Foundation

// MARK: - AppBadge

/// What an application's Dock tile shows over its icon.
///
/// Read from the tile's status label, so it is whatever the application
/// handed its dock tile: a count, a short word, or a bare dot.
enum AppBadge: Equatable, Sendable {
  /// A count of one or more.
  case count(Int)
  /// Any other wording, kept as the application spelled it.
  case text(String)
  /// A dot with no wording. The Dock draws a blank label this way.
  case mark

  // MARK: Lifecycle

  /// Sorts a status label into a badge, or nil when the tile shows none.
  ///
  /// Only ASCII digits make a count: a label in other digits is drawn as
  /// written rather than read as a number. Zero stays wording, because
  /// the Dock draws it as given and a count of nothing is not what it shows.
  init?(statusLabel: String?) {
    guard let statusLabel, !statusLabel.isEmpty else {
      return nil
    }
    let trimmed = statusLabel.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty {
      self = .mark
    } else if trimmed.allSatisfy({ $0.isASCII && $0.isNumber }), trimmed.contains(where: { $0 != "0" }) {
      // Digits past what an Int holds still mean a large count.
      self = .count(Int(trimmed) ?? Int.max)
    } else {
      self = .text(statusLabel)
    }
  }

  // MARK: Internal

  /// The wording drawn inside the badge. Long counts round down to a
  /// fixed width, so the badge stays beside the icon it belongs to.
  var displayText: String {
    switch self {
    case .count(let value):
      value > 999 ? "999+" : String(value)
    case .text(let wording):
      wording
    case .mark:
      ""
    }
  }
}

// MARK: - AppBadges

/// The badges one appearance of the panel draws, by owning process.
///
/// Built once as the panel goes up and left alone until the next one,
/// so a badge that changes while the panel is open waits for the next
/// opening rather than redrawing rows under the user.
struct AppBadges: Equatable, Sendable {
  static let none = AppBadges(byProcess: [:])

  let byProcess: [pid_t: AppBadge]

  /// The badge for a row. Window rows and the row of an application with
  /// no window are looked up the same way, so every row of one
  /// application shows the same badge.
  func badge(for window: WindowItem) -> AppBadge? {
    byProcess[window.ownerProcessIdentifier]
  }
}
