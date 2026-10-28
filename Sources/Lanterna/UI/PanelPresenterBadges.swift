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

  /// Writes down a Dock that could not be read, once per reason. A Dock
  /// that stays down, as while it restarts, would otherwise add a line to
  /// every appearance. Running out of time is the press's budget, not a
  /// fault, and stays in the panel line's columns only.
  func noteUnreadableDock(_ reading: BadgeReading?) {
    guard let reading else {
      return
    }
    let reason: String
    switch reading.outcome {
    case .read:
      lastReportedBadgeFailure = nil
      return

    case .late:
      return

    case .failed(let failure):
      reason = failure

    case .noDock:
      reason = "noDock"
    }
    guard reason != lastReportedBadgeFailure else {
      return
    }
    lastReportedBadgeFailure = reason
    writeLine(LogLine(
      .warning,
      .panel,
      "dock badges unreadable (\(reason)); rows show no badges until a read succeeds"
    ))
  }

  // MARK: Private

  /// The time from press to panel the panel is held to.
  private static let showBudget = Duration.milliseconds(100)

  /// Kept back for the work that follows the read: drawing the rows and
  /// asking for the keyboard.
  private static let roomAfterRead = Duration.milliseconds(20)

}
