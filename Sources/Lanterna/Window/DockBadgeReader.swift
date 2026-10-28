import Foundation

// MARK: - BadgeReading

/// One read of the Dock's badges, as the panel goes up.
struct BadgeReading: Equatable, Sendable {

  /// How the read ended. Only a finished read is drawn; the others leave
  /// every row without a badge for that appearance.
  enum Outcome: Equatable, Sendable {
    /// Every tile was read in time.
    case read
    /// The deadline passed. What was read by then is dropped rather than
    /// drawn, so a row without a badge never means a badge that was not
    /// reached.
    case late
    /// The Dock could not be read: it answered with an error, named the
    /// way the window reader names one, or answered in a shape it never
    /// uses.
    case failed(reason: String)
    /// No Dock process to ask, as while it restarts.
    case noDock
  }

  let badges: AppBadges
  let outcome: Outcome
  let elapsed: Duration

}

// MARK: - DockBadgeReading

/// Reads the badges on the Dock's application tiles.
@MainActor
protocol DockBadgeReading {
  /// Reads every tile once, giving up whole once the deadline passes.
  func read(deadline: Duration) -> BadgeReading
}

// MARK: - FixedDockBadgeReader

/// Hands back a table decided in advance, for the sample rows: those
/// belong to no running process, so the live Dock has nothing for them.
struct FixedDockBadgeReader: DockBadgeReading {
  let badges: AppBadges

  func read(deadline _: Duration) -> BadgeReading {
    BadgeReading(badges: badges, outcome: .read, elapsed: .zero)
  }
}
