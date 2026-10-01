import Foundation
import Logging

/// The shape of a saved launch file: one header line, then one line per
/// entry, each a JSON object.
enum LaunchLogCoding {

  // MARK: Internal

  /// The only header version this build reads. A file of any other
  /// version is skipped whole.
  static let formatVersion = 1

  /// The header line, newline included.
  static func header(launch: LaunchID, version: String, utcOffsetSeconds: Int) -> String {
    "{\"format\":\(formatVersion),"
      + "\"launch\":\(ContextValue.jsonString(launch.stamp)),"
      + "\"utcOffset\":\(ContextValue.jsonString(LogTimeText.offset(utcOffsetSeconds))),"
      + "\"version\":\(ContextValue.jsonString(version))}\n"
  }

  /// One entry's line, newline included. Written under the store's lock,
  /// so it is assembled by hand rather than through an encoder.
  static func line(for entry: Diagnostics.LogEntry) -> String {
    "{\"seq\":\(entry.sequence),"
      + "\"ts\":\(Int64((entry.capturedAt.timeIntervalSince1970 * 1000).rounded(.down))),"
      + "\"level\":\(ContextValue.jsonString(entry.level.rawValue)),"
      + "\"category\":\(ContextValue.jsonString(entry.category.rawValue)),"
      + "\"message\":\(ContextValue.jsonString(entry.message)),"
      + "\"source\":\(ContextValue.jsonString(entry.source)),"
      + "\"context\":\(ContextValue.jsonObject(entry.context))}\n"
  }

  /// Whether `line` is a header this build reads.
  static func isReadableHeader(_ line: Data) -> Bool {
    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
      return false
    }
    return (object["format"] as? NSNumber)?.intValue == formatVersion
  }

  /// One entry read back, or nil for a line that is not one (cut short,
  /// damaged, or naming a level or category this build does not know).
  static func entry(from line: Data, launch: LaunchID) -> Diagnostics.LogEntry? {
    guard
      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
      let sequence = (object["seq"] as? NSNumber)?.uint64Value, sequence > 0,
      let milliseconds = (object["ts"] as? NSNumber)?.int64Value,
      let levelWord = object["level"] as? String,
      let level = Logger.Level(rawValue: levelWord),
      let categoryWord = object["category"] as? String,
      let category = LogCategory(rawValue: categoryWord),
      let message = object["message"] as? String,
      let source = object["source"] as? String
    else { return nil }
    return Diagnostics.LogEntry(
      launch: launch,
      sequence: sequence,
      capturedAt: Date(timeIntervalSince1970: Double(milliseconds) / 1000),
      level: DiagnosticLogHandler.recordedLevel(level),
      category: category,
      message: message,
      source: source,
      context: context(from: object["context"])
    )
  }

  // MARK: Private

  private static func context(from value: Any?) -> [String: ContextValue] {
    guard let dictionary = value as? [String: Any] else { return [:] }
    return dictionary.compactMapValues(contextValue)
  }

  private static func contextValue(_ value: Any) -> ContextValue? {
    switch value {
    case let text as String:
      return .string(text)

    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return .bool(number.boolValue)
      }
      if CFNumberIsFloatType(number) {
        return .double(number.doubleValue)
      }
      return .int(number.intValue)

    default:
      return nil
    }
  }

}
