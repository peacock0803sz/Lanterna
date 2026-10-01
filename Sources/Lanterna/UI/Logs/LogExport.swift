import Foundation

/// The shapes lines leave the log window in: text for ⌘C and Copy, JSON
/// Lines for Export…. Separators are never written.
enum LogExport {

  /// One line per entry: launch, number, time, level, category, message,
  /// one space apart. Line breaks in a message become `⏎`.
  static func copyText(_ entries: [Diagnostics.LogEntry], timeZone: TimeZone = .current) -> String {
    entries.lazy.map { copyLine($0, timeZone: timeZone) }.joined(separator: "\n")
  }

  static func copyLine(_ entry: Diagnostics.LogEntry, timeZone: TimeZone = .current) -> String {
    [
      entry.launch.stamp,
      "#\(entry.sequence)",
      LogTimeText.clock(entry.capturedAt, timeZone: timeZone),
      entry.level.shortName,
      entry.category.rawValue,
      entry.oneLineMessage,
    ].joined(separator: " ")
  }

  /// One JSON object per entry, each ending in a newline. Fields in a
  /// fixed order, written by hand so the order holds; every field is
  /// written whichever columns are showing.
  static func jsonLines(_ entries: [Diagnostics.LogEntry], timeZone: TimeZone = .current) -> String {
    entries.map { jsonLine($0, timeZone: timeZone) + "\n" }.joined()
  }

  static func jsonLine(_ entry: Diagnostics.LogEntry, timeZone: TimeZone = .current) -> String {
    let fields = [
      ("launch", ContextValue.jsonString(entry.launch.stamp)),
      ("seq", String(entry.sequence)),
      ("time", ContextValue.jsonString(LogTimeText.iso(entry.capturedAt, timeZone: timeZone))),
      ("level", ContextValue.jsonString(entry.level.rawValue)),
      ("category", ContextValue.jsonString(entry.category.rawValue)),
      ("message", ContextValue.jsonString(entry.message)),
      ("source", ContextValue.jsonString(entry.source)),
      ("context", ContextValue.jsonObject(entry.context)),
    ]
    return "{" + fields.lazy.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",") + "}"
  }

  /// `Lanterna Logs 2026-10-01 20-15-03.jsonl`, local time.
  static func defaultFileName(at date: Date, timeZone: TimeZone = .current) -> String {
    let stamp = LogTimeText.full(date, timeZone: timeZone)
      .prefix(19)
      .replacing(":", with: "-")
    return "Lanterna Logs \(stamp).jsonl"
  }

}
