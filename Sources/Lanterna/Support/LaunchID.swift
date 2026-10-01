import Foundation

/// One run of the app, named by when it started.
///
/// The stamp is the start time in local time to the millisecond
/// (`2026-09-30 14:02:10.481`), short and readable, sorting by name in time
/// order. Two runs from the same origin that start in the same millisecond
/// are told apart by a `-2`, `-3`… suffix. The file name carries the same
/// instant in a path-safe shape (`20260930-140210.481`) and reads back into
/// the stamp.
struct LaunchID: Hashable, Sendable {

  // MARK: Lifecycle

  init(startedAt: Date, suffix: Int? = nil, isCurrent: Bool, timeZone: TimeZone = .current) {
    let parts = Self.parts(of: startedAt, in: timeZone)
    self.startedAt = startedAt
    self.suffix = suffix
    self.isCurrent = isCurrent
    stamp = String(
      format: "%04d-%02d-%02d %02d:%02d:%02d.%03d",
      parts.year,
      parts.month,
      parts.day,
      parts.hour,
      parts.minute,
      parts.second,
      parts.millisecond
    ) + Self.suffixText(suffix)
    fileBaseName = String(
      format: "%04d%02d%02d-%02d%02d%02d.%03d",
      parts.year,
      parts.month,
      parts.day,
      parts.hour,
      parts.minute,
      parts.second,
      parts.millisecond
    ) + Self.suffixText(suffix)
  }

  // MARK: Internal

  /// What the separator rows, copies and exports show.
  let stamp: String
  let startedAt: Date
  /// The `-N` that told this run apart from another started in the same
  /// millisecond, or nil for the first.
  let suffix: Int?
  /// Whether this is the run reading it.
  let isCurrent: Bool
  /// The file name without its extension.
  let fileBaseName: String

  var fileName: String {
    fileBaseName + ".jsonl"
  }

  /// Reads a saved file's name back into the run that wrote it. Nil for a
  /// name of any other shape.
  static func fromFileName(_ name: String, timeZone: TimeZone = .current) -> LaunchID? {
    guard name.hasSuffix(".jsonl") else { return nil }
    let base = String(name.dropLast(".jsonl".count))
    // 8 digits, '-', 6 digits, '.', 3 digits, then an optional "-N".
    let fixed = base.prefix(19)
    let rest = base.dropFirst(19)
    let characters = Array(fixed)
    guard
      characters.count == 19,
      characters[8] == "-",
      characters[15] == ".",
      characters.enumerated().allSatisfy({ index, character in
        index == 8 || index == 15 || character.isASCII && character.isNumber
      })
    else { return nil }
    var suffix: Int?
    if !rest.isEmpty {
      guard rest.first == "-", let number = Int(rest.dropFirst()), number >= 2 else { return nil }
      suffix = number
    }
    func number(_ range: Range<Int>) -> Int {
      Int(String(characters[range])) ?? 0
    }
    var components = DateComponents()
    components.calendar = Self.calendar(in: timeZone)
    components.timeZone = timeZone
    components.year = number(0 ..< 4)
    components.month = number(4 ..< 6)
    components.day = number(6 ..< 8)
    components.hour = number(9 ..< 11)
    components.minute = number(11 ..< 13)
    components.second = number(13 ..< 15)
    guard let whole = components.date else { return nil }
    let startedAt = whole.addingTimeInterval(Double(number(16 ..< 19)) / 1000)
    let launch = LaunchID(startedAt: startedAt, suffix: suffix, isCurrent: false, timeZone: timeZone)
    // A name that names no real instant (month 13) would not read back the same.
    guard launch.fileBaseName == base else { return nil }
    return launch
  }

  static func ==(lhs: LaunchID, rhs: LaunchID) -> Bool {
    lhs.stamp == rhs.stamp
  }

  /// The same run with the next `-N`, for when its file name is taken.
  func nextSuffix(timeZone: TimeZone = .current) -> LaunchID {
    LaunchID(startedAt: startedAt, suffix: (suffix ?? 1) + 1, isCurrent: isCurrent, timeZone: timeZone)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(stamp)
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

  private static func suffixText(_ suffix: Int?) -> String {
    suffix.map { "-\($0)" } ?? ""
  }

  private static func calendar(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  /// Truncates to the millisecond rather than rounding, so the stamp never
  /// names an instant after the start. The small allowance keeps a time
  /// read back from a file name (481 ms stored as 480.9999…) on its own
  /// millisecond.
  private static func parts(of date: Date, in timeZone: TimeZone) -> Parts {
    let wholeSeconds = date.timeIntervalSinceReferenceDate.rounded(.down)
    let fraction = (date.timeIntervalSinceReferenceDate - wholeSeconds) * 1000
    let millisecond = Int((fraction + 1e-4).rounded(.down))
    let components = calendar(in: timeZone).dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: Date(timeIntervalSinceReferenceDate: wholeSeconds)
    )
    return Parts(
      year: components.year ?? 0,
      month: components.month ?? 0,
      day: components.day ?? 0,
      hour: components.hour ?? 0,
      minute: components.minute ?? 0,
      second: components.second ?? 0,
      millisecond: min(millisecond, 999)
    )
  }

}
