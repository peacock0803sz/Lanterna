import Foundation

/// The fixed time shapes the diagnostics log shows and writes.
///
/// Built from calendar parts rather than a locale-aware formatter, so a
/// report reads the same in every locale.
enum LogTimeText {

  // MARK: Internal

  /// `14:02:20.118`, local time.
  static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
    let parts = parts(of: date, in: timeZone)
    return String(format: "%02d:%02d:%02d.%03d", parts.hour, parts.minute, parts.second, parts.millisecond)
  }

  /// `2026-09-30 14:02:20.118`, local time.
  static func full(_ date: Date, timeZone: TimeZone = .current) -> String {
    let parts = parts(of: date, in: timeZone)
    return String(format: "%04d-%02d-%02d ", parts.year, parts.month, parts.day) + clock(date, timeZone: timeZone)
  }

  /// `20260930-140220.118`, local time, safe in a file name.
  static func fileStamp(_ date: Date, timeZone: TimeZone = .current) -> String {
    let parts = parts(of: date, in: timeZone)
    return String(
      format: "%04d%02d%02d-%02d%02d%02d.%03d",
      parts.year,
      parts.month,
      parts.day,
      parts.hour,
      parts.minute,
      parts.second,
      parts.millisecond
    )
  }

  /// `2026-09-30T14:02:20.118+09:00`, local time with its offset.
  static func iso(_ date: Date, timeZone: TimeZone = .current) -> String {
    let parts = parts(of: date, in: timeZone)
    return String(format: "%04d-%02d-%02dT", parts.year, parts.month, parts.day)
      + clock(date, timeZone: timeZone)
      + offset(timeZone.secondsFromGMT(for: date))
  }

  /// `+09:00`, `-04:30`, `+00:00`.
  static func offset(_ seconds: Int) -> String {
    let sign = seconds < 0 ? "-" : "+"
    let minutes = abs(seconds) / 60
    return sign + String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }

  // MARK: Private

  private struct Parts {
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int
    let millisecond: Int
  }

  /// Truncates to the millisecond rather than rounding, so a launch stamp
  /// never names an instant after the start. The small allowance keeps a
  /// time read back from a file name (481 ms stored as 480.9999…) on its
  /// own millisecond.
  private static func parts(of date: Date, in timeZone: TimeZone) -> Parts {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let whole = date.timeIntervalSinceReferenceDate.rounded(.down)
    let fraction = (date.timeIntervalSinceReferenceDate - whole) * 1000
    let components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: Date(timeIntervalSinceReferenceDate: whole)
    )
    return Parts(
      year: components.year ?? 0,
      month: components.month ?? 0,
      day: components.day ?? 0,
      hour: components.hour ?? 0,
      minute: components.minute ?? 0,
      second: components.second ?? 0,
      millisecond: min(Int((fraction + 1e-4).rounded(.down)), 999)
    )
  }

}
