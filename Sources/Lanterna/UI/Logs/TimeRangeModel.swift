import Foundation

// MARK: - TimeSpanUnit

/// The unit beside an amount in the time picker.
enum TimeSpanUnit: String, CaseIterable, Equatable {
  case seconds
  case minutes
  case hours
  case days

  // MARK: Internal

  var short: String {
    switch self {
    case .seconds: "s"
    case .minutes: "m"
    case .hours: "h"
    case .days: "d"
    }
  }

  var milliseconds: Int64 {
    switch self {
    case .seconds: 1_000
    case .minutes: 60_000
    case .hours: 3_600_000
    case .days: 86_400_000
    }
  }
}

// MARK: - RelativeNowChoice

/// The now-relative half of the picker.
enum RelativeNowChoice: Equatable {
  case presetFiveMinutes
  case presetQuarterHour
  case presetHour
  case presetSixHours
  case presetDay
  case presetWeek
  case last(amount: Int, unit: TimeSpanUnit)
  case sinceLaunch
  case allKept
}

// MARK: - AnchoredStyle

/// How a span hangs off an anchor moment.
enum AnchoredStyle: String, CaseIterable, Equatable {
  case around
  case before
  case after

  var title: String {
    switch self {
    case .around: "Around"
    case .before: "Before"
    case .after: "After"
    }
  }
}

// MARK: - TimeRangeSelection

/// What the toolbar time control holds.
///
/// The picker edits a draft of this value and only writes it back
/// on Apply. Resolving turns it into bounds plus the short toolbar
/// text and the query tokens the window writes into the filter.
struct TimeRangeSelection: Equatable {
  enum Kind: Equatable {
    case relativeNow
    case anchored
    case custom
  }

  static var fallback: TimeRangeSelection {
    TimeRangeSelection()
  }

  var kind = Kind.relativeNow
  var relative = RelativeNowChoice.presetHour
  var anchoredStyle = AnchoredStyle.around
  var anchor = Date()
  var spanAmount = 5
  var spanUnit = TimeSpanUnit.minutes
  var lastAmount = 15
  var lastUnit = TimeSpanUnit.minutes
  var customStart = Date().addingTimeInterval(-3_600)
  var customEnd = Date()
}

// MARK: - TimeRangeResolve

/// Resolved bounds plus display strings for a selection.
struct TimeRangeResolve: Equatable {
  var startMilliseconds: Int64?
  var endMilliseconds: Int64?
  var shortLabel: String
  var preview: String
  var queryTokens: [String]
}

// MARK: - TimeRangeResolver

/// Turns a selection into bounds, labels, and filter tokens.
enum TimeRangeResolver {

  // MARK: Internal

  static func resolve(
    _ selection: TimeRangeSelection,
    now: Date = Date(),
    launchStart: Date? = nil
  ) -> TimeRangeResolve {
    switch selection.kind {
    case .relativeNow:
      resolveRelative(selection.relative, now: now, launchStart: launchStart)

    case .anchored:
      resolveAnchored(
        style: selection.anchoredStyle,
        anchor: selection.anchor,
        amount: max(selection.spanAmount, 1),
        unit: selection.spanUnit
      )

    case .custom:
      resolveCustom(start: selection.customStart, end: selection.customEnd)
    }
  }

  // MARK: Private

  private static func resolveRelative(
    _ choice: RelativeNowChoice,
    now: Date,
    launchStart: Date?
  ) -> TimeRangeResolve {
    let nowMs = milliseconds(of: now)
    switch choice {
    case .presetFiveMinutes:
      return spanwstring(nowMs: nowMs, lengthMs: 5 * 60_000, label: "Last 5 minutes")

    case .presetQuarterHour:
      return spanwstring(nowMs: nowMs, lengthMs: 15 * 60_000, label: "Last 15 minutes")

    case .presetHour:
      return spanwstring(nowMs: nowMs, lengthMs: 3_600_000, label: "Last 1 hour")

    case .presetSixHours:
      return spanwstring(nowMs: nowMs, lengthMs: 6 * 3_600_000, label: "Last 6 hours")

    case .presetDay:
      return spanwstring(nowMs: nowMs, lengthMs: 86_400_000, label: "Last 24 hours")

    case .presetWeek:
      return spanwstring(nowMs: nowMs, lengthMs: 7 * 86_400_000, label: "Last 7 days")

    case .last(let amount, let unit):
      let safe = max(amount, 1)
      let length = Int64(safe) * unit.milliseconds
      return spanwstring(nowMs: nowMs, lengthMs: length, label: "Last \(safe) \(unit.rawValue)")

    case .sinceLaunch:
      let startMs = launchStart.map(milliseconds(of:))
      return TimeRangeResolve(
        startMilliseconds: startMs,
        endMilliseconds: nowMs,
        shortLabel: "Since this launch",
        preview: previewText(startMs: startMs, endMs: nowMs),
        queryTokens: tokens(startMs: startMs, endMs: nil)
      )

    case .allKept:
      return TimeRangeResolve(
        startMilliseconds: nil,
        endMilliseconds: nil,
        shortLabel: "All kept",
        preview: "All kept",
        queryTokens: []
      )
    }
  }

  private static func spanwstring(nowMs: Int64, lengthMs: Int64, label: String) -> TimeRangeResolve {
    let startMs = nowMs - lengthMs
    return TimeRangeResolve(
      startMilliseconds: startMs,
      endMilliseconds: nowMs,
      shortLabel: label,
      preview: previewText(startMs: startMs, endMs: nowMs),
      queryTokens: tokens(startMs: startMs, endMs: nowMs)
    )
  }

  private static func resolveAnchored(
    style: AnchoredStyle,
    anchor: Date,
    amount: Int,
    unit: TimeSpanUnit
  ) -> TimeRangeResolve {
    let anchorMs = milliseconds(of: anchor)
    let span = Int64(amount) * unit.milliseconds
    let clock = clockText(of: anchor)
    switch style {
    case .around:
      let startMs = anchorMs - span
      let endMs = anchorMs + span
      return TimeRangeResolve(
        startMilliseconds: startMs,
        endMilliseconds: endMs,
        shortLabel: "Around \(clock) ±\(amount)\(unit.short)",
        preview: "= \(fullText(milliseconds: startMs)) – \(fullText(milliseconds: endMs))",
        queryTokens: tokens(startMs: startMs, endMs: endMs)
      )

    case .before:
      let startMs = anchorMs - span
      return TimeRangeResolve(
        startMilliseconds: startMs,
        endMilliseconds: anchorMs,
        shortLabel: "Before \(clock) \(amount)\(unit.short)",
        preview: "= \(fullText(milliseconds: startMs)) – \(fullText(milliseconds: anchorMs))",
        queryTokens: tokens(startMs: startMs, endMs: anchorMs)
      )

    case .after:
      let endMs = anchorMs + span
      return TimeRangeResolve(
        startMilliseconds: anchorMs,
        endMilliseconds: endMs,
        shortLabel: "After \(clock) \(amount)\(unit.short)",
        preview: "= \(fullText(milliseconds: anchorMs)) – \(fullText(milliseconds: endMs))",
        queryTokens: tokens(startMs: anchorMs, endMs: endMs)
      )
    }
  }

  private static func resolveCustom(start: Date, end: Date) -> TimeRangeResolve {
    let ordered = start <= end ? (start, end) : (end, start)
    let startMs = milliseconds(of: ordered.0)
    let endMs = milliseconds(of: ordered.1)
    return TimeRangeResolve(
      startMilliseconds: startMs,
      endMilliseconds: endMs,
      shortLabel: "\(shortDayText(of: ordered.0)) \(clockText(of: ordered.0)) – \(clockText(of: ordered.1))",
      preview: "= \(fullText(milliseconds: startMs)) – \(fullText(milliseconds: endMs))",
      queryTokens: tokens(startMs: startMs, endMs: endMs)
    )
  }

  private static func milliseconds(of date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1_000)
  }

  private static func tokens(startMs: Int64?, endMs: Int64?) -> [String] {
    var out = [String]()
    if let startMs {
      out.append("after:\(isoText(milliseconds: startMs))")
    }
    if let endMs {
      out.append("before:\(isoText(milliseconds: endMs))")
    }
    return out
  }

  private static func isoText(milliseconds: Int64) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1_000))
  }

  private static func clockText(of date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
  }

  private static func shortDayText(of date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MM-dd"
    return formatter.string(from: date)
  }

  private static func fullText(milliseconds: Int64) -> String {
    LogExport.fullTime(milliseconds: milliseconds)
  }

  private static func previewText(startMs: Int64?, endMs: Int64?) -> String {
    switch (startMs, endMs) {
    case (.some(let start), .some(let end)):
      "= \(fullText(milliseconds: start)) – \(fullText(milliseconds: end))"
    case (.some(let start), .none):
      "= \(fullText(milliseconds: start)) – now"
    case (.none, .some(let end)):
      "= kept start – \(fullText(milliseconds: end))"
    case (.none, .none):
      "All kept"
    }
  }

}
