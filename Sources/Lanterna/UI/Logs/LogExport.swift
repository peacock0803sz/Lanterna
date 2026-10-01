import Foundation

// MARK: - LogExport

/// Formats visible rows for copying and file export.
///
/// Text copy carries one line per row with the on-screen fields.
/// JSON Lines and file export always carry the stored hierarchy,
/// including the launch and the build that emitted each row.
enum LogExport {

  // MARK: Internal

  /// One text line per row, pastable into a report.
  static func textLines(rows: [DiagnosticRow]) -> String {
    rows.map(textLine(for:)).joined(separator: "\n")
  }

  /// One JSON object per row, keeping nested payload structure.
  static func jsonLines(rows: [DiagnosticRow]) -> String {
    rows.map(jsonLine(for:)).joined(separator: "\n")
  }

  /// File contents for the save panel. Always the payload form,
  /// so a file never drops context the table had.
  static func fileContents(rows: [DiagnosticRow]) -> String {
    let body = jsonLines(rows: rows)
    return body.isEmpty ? "" : body + "\n"
  }

  /// Short clock time with milliseconds, as the table shows it.
  static func displayTime(milliseconds: Int64) -> String {
    shortFormatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1000))
  }

  /// Full stamp with date, as copied text and detail use it.
  static func fullTime(milliseconds: Int64) -> String {
    fullFormatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1000))
  }

  // MARK: Private

  private static let shortFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  private static let fullFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter
  }()

  private static func textLine(for row: DiagnosticRow) -> String {
    let level = displayLevel(row.level)
    let category = row.category ?? "-"
    return "#\(row.sequence) \(fullTime(milliseconds: row.recordedAtMilliseconds)) \(level) \(category) \(row.message)"
  }

  private static func displayLevel(_ level: String) -> String {
    switch level.lowercased() {
    case "warning",
         "warn":
      "WARN"
    case "error":
      "ERROR"
    case "info":
      "INFO"
    case "debug":
      "DEBUG"
    default:
      level.uppercased()
    }
  }

  private static func jsonLine(for row: DiagnosticRow) -> String {
    var object: [String: Any] = [
      "seq": row.sequence,
      "timestamp_ms": row.recordedAtMilliseconds,
      "time": fullTime(milliseconds: row.recordedAtMilliseconds),
      "level": row.level,
      "message": row.message,
    ]
    if let category = row.category {
      object["category"] = category
    } else {
      object["category"] = NSNull()
    }
    if let launchID = row.launchID {
      object["launch_id"] = launchID
    } else {
      object["launch_id"] = NSNull()
    }
    if let buildVersion = row.buildVersion {
      object["build_version"] = buildVersion
    } else {
      object["build_version"] = NSNull()
    }
    if let payloadText = row.payloadJSON, let data = payloadText.data(using: .utf8) {
      if let payload = try? JSONSerialization.jsonObject(with: data) {
        object["payload"] = payload
      } else {
        object["payload"] = NSNull()
      }
    } else {
      object["payload"] = NSNull()
    }
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    return String(data: data, encoding: .utf8) ?? "{}"
  }

}
