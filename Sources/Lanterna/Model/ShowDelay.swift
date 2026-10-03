import Foundation

// MARK: - ShowDelay

/// The panel show delay in milliseconds: one key, validated in one place.
///
/// The configuration file spells a millisecond count; the settings
/// stepper spells the same count. Both meet here, so validation and
/// display share one table instead of two. Absent or zero means off.
enum ShowDelay: Sendable {

  // MARK: Internal

  /// The wait a fresh opt-in uses, in milliseconds. Long enough to
  /// swallow a quick tap, short enough to read as slight.
  static let defaultMilliseconds = 150.0

  /// The longest wait the file or the stepper can ask for, in
  /// milliseconds. Past this a press reads as broken rather than
  /// delayed.
  static let maximumMilliseconds = 1000.0

  /// One step of the settings stepper, in milliseconds. Finer steps
  /// cannot be told apart by feel.
  static let settingsStep = 50.0

  /// The note for a count that spells no wait at all, naming the
  /// default it fell back to.
  static var invalidIssue: String {
    "showDelayMs is not a valid value; using \(Int(defaultMilliseconds))"
  }

  /// The wait one run uses, with the note when one is owed.
  ///
  /// Absent or zero means off. Past the maximum clamps to it. Negative
  /// or unreadable counts fall back to the default. Idempotent, so both
  /// the file reader and the settings snapshot can call it.
  static func effective(_ milliseconds: Double?) -> (value: Double?, issue: String?) {
    guard let milliseconds, milliseconds.isFinite else {
      if milliseconds == nil {
        return (nil, nil)
      }
      return (defaultMilliseconds, ShowDelay.invalidIssue)
    }
    if milliseconds == 0 {
      return (nil, nil)
    }
    if milliseconds < 0 {
      return (defaultMilliseconds, ShowDelay.invalidIssue)
    }
    if milliseconds > maximumMilliseconds {
      return (maximumMilliseconds, ShowDelay.cappedIssue)
    }
    return (milliseconds, nil)
  }

  // MARK: Private

  /// The note for a count past the maximum, naming the wait it became.
  private static var cappedIssue: String {
    "showDelayMs is above the maximum; using \(Int(maximumMilliseconds))"
  }

}
