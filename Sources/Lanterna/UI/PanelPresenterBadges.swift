// MARK: - PanelPresenter + Dock badges

extension PanelPresenter {

  // MARK: Internal

  /// How long one appearance may spend reading the Dock. Twice the slow
  /// end of what a read took on a warmed connection, so an ordinary read
  /// fits with room to spare while a wedged Dock still cannot hold the
  /// panel back for long.
  static let badgeReadDeadline = Duration.milliseconds(32)

  /// The table an appearance draws: only a finished read. A read that ran
  /// out of time or failed draws nothing, so a row without a badge never
  /// stands for a badge that was not reached.
  static func drawnBadges(of reading: BadgeReading?) -> AppBadges {
    guard let reading, reading.outcome == .read else {
      return .none
    }
    return reading.badges
  }

  /// Reads the Dock's badges for the appearance going up, or nothing
  /// when the badges are off and the Dock is not asked at all.
  ///
  /// The read sits inside the time from press to panel, so it gets only
  /// what is left of that time: a press that already waited for its list
  /// may have none left, and then the appearance goes up without badges
  /// rather than late.
  func readBadgesForAppearance(startedAt: ContinuousClock.Instant) -> BadgeReading? {
    guard appIconBadges else {
      return nil
    }
    let spent = now() - startedAt
    let deadline = min(Self.badgeReadDeadline, Self.showBudget - spent - Self.roomAfterRead)
    guard deadline >= .milliseconds(1) else {
      return BadgeReading(badges: .none, outcome: .late, elapsed: .zero)
    }
    return badgeReader.read(deadline: deadline)
  }

  // MARK: Private

  /// The time from press to panel the panel is held to.
  private static let showBudget = Duration.milliseconds(100)

  /// Kept back for the work that follows the read: drawing the rows and
  /// asking for the keyboard.
  private static let roomAfterRead = Duration.milliseconds(20)

}
