import Foundation

// MARK: - LogQuery

/// What the query row holds: either a lightweight filter string or a
/// read-only database statement. The two never mix; switching rows
/// drops the conditions rather than converting them.
///
/// The lightweight row stays the default with its guide beside it.
/// The database row is the escape hatch for conditions the compact
/// syntax cannot say.
struct LogQuery: Equatable, Sendable {
  /// Which syntax the row speaks.
  enum Mode: Equatable, Sendable {
    case lightweight
    case database
  }

  /// Starts a fresh row: lightweight, empty, default time window.
  static var fresh: LogQuery {
    LogQuery()
  }

  /// The active syntax.
  var mode = Mode.lightweight
  /// The filter string. Source of truth while in lightweight mode.
  var lightweightText = ""
  /// The statement text. Source of truth while in database mode.
  var databaseText = ""

  /// The conditions currently in force: the row text of the active
  /// mode, or nothing when the row is empty.
  var activeText: String {
    switch mode {
    case .lightweight: lightweightText
    case .database: databaseText
    }
  }
}

// MARK: - SQLLiteral

/// One bound value travelling with a translated filter. The
/// executor inlines these with quoting, so translation never
/// concatenates caller text into the statement.
enum SQLLiteral: Equatable, Sendable {
  case text(String)
  case integer(Int64)
  case real(Double)
}

// MARK: - FilterCondition

/// One parsed condition: its SQL fragment with `?` markers, the
/// values for those markers, the chip text shown, and the source
/// token the chip removes.
struct FilterCondition: Equatable, Sendable {
  var fragment: String
  var values: [SQLLiteral]
  var chip: String
  var source: String
}

// MARK: - TranslatedFilter

/// A parsed lightweight row: ANDed conditions plus the chips.
/// Removing a chip drops its condition by deleting the source
/// token from the row text.
struct TranslatedFilter: Equatable, Sendable {
  var conditions: [FilterCondition]

  /// The combined predicate, or a match-all when empty.
  var predicate: String {
    guard !conditions.isEmpty else {
      return "1 = 1"
    }
    return conditions.lazy.map { "(\($0.fragment))" }.joined(separator: " AND ")
  }

  /// Values in fragment order.
  var values: [SQLLiteral] {
    conditions.flatMap(\.values)
  }

  /// The row text without one chip's condition.
  func removingChip(_ chip: String) -> String {
    conditions.filter { $0.chip != chip }.map(\.source).joined(separator: " ")
  }
}

// MARK: - LightweightFilter

/// Reads the compact filter syntax into translated conditions.
///
/// Tokens split on whitespace outside double quotes. `field:value`
/// contains, `field=value` matches exactly, `field!=value`
/// excludes. Levels compare in debug, info, warning, error order.
/// Anything else searches the message. Dotted paths read the
/// payload, with `[]` matching any array element. `after:` and
/// `before:` bound the recorded time.
enum LightweightFilter {

  // MARK: Internal

  /// Parses one row. Unrecognized tokens fall back to message
  /// search, except malformed level comparisons, which match
  /// nothing so the empty result stays explainable by its chip.
  static func parse(_ text: String) -> TranslatedFilter {
    var conditions = [FilterCondition]()
    for token in tokens(in: text) {
      if let condition = condition(for: token) {
        conditions.append(condition)
      }
    }
    return TranslatedFilter(conditions: conditions)
  }

  // MARK: Private

  private static let levelOrder = ["debug", "info", "warning", "error"]

  private static func tokens(in text: String) -> [String] {
    var out = [String]()
    var current = ""
    var quoted = false
    for character in text {
      if character == "\"" {
        quoted.toggle()
        current.append(character)
      } else if character.isWhitespace, !quoted {
        if !current.isEmpty {
          out.append(current)
          current = ""
        }
      } else {
        current.append(character)
      }
    }
    if !current.isEmpty {
      out.append(current)
    }
    return out
  }

  private static func condition(for token: String) -> FilterCondition? {
    let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    guard let split = splitOperator(in: token) else {
      return messageContains(bare, source: token)
    }
    let key = String(split.key).lowercased()
    let rawValue = String(split.value).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    switch (key, split.op) {
    case ("level", _):
      return levelCondition(op: split.op, word: rawValue.lowercased(), source: token)
    case ("category", ":"):
      return containsCondition(column: "category", value: rawValue, chip: "Category: \(rawValue)", source: token)
    case ("category", "="):
      return exactCondition(column: "category", value: rawValue, chip: "Category is \(rawValue)", source: token)
    case ("category", "!="):
      return excludedCondition(column: "category", value: rawValue, chip: "Category is not \(rawValue)", source: token)
    case ("message", ":"):
      return messageContains(rawValue, source: token)
    case ("launch", _):
      return exactCondition(column: "launch_id", value: rawValue, chip: "Launch: \(rawValue)", source: token)
    case ("version", _):
      return exactCondition(column: "build_version", value: rawValue, chip: "Version: \(rawValue)", source: token)
    case ("after", ":"):
      return timeCondition(bound: rawValue, lower: true, source: token)
    case ("before", ":"):
      return timeCondition(bound: rawValue, lower: false, source: token)
    default:
      if split.op == ":", !looksLikePath(key) {
        return messageContains(bare, source: token)
      }
      return payloadCondition(path: key, op: split.op, value: rawValue, source: token)
    }
  }

  private static func splitOperator(in token: String) -> (key: Substring, op: String, value: Substring)? {
    let operators = ["!=", ">=", "<=", "=", ">", "<", ":"]
    var index = token.startIndex
    var quoted = false
    while index < token.endIndex {
      let character = token[index]
      if character == "\"" {
        quoted.toggle()
      } else if !quoted {
        for op in operators {
          if token[index...].hasPrefix(op) {
            let key = token[..<index]
            let value = token[token.index(index, offsetBy: op.count)...]
            if !key.isEmpty, !value.isEmpty {
              return (key, op, value)
            }
            return nil
          }
        }
      }
      index = token.index(after: index)
    }
    return nil
  }

  private static func looksLikePath(_ key: String) -> Bool {
    guard let first = key.first, first.isLetter || first == "_" else {
      return false
    }
    return key.contains(".") || key.contains("[]")
      || key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
  }

  private static func messageContains(_ value: String, source: String) -> FilterCondition? {
    guard !value.isEmpty else {
      return nil
    }
    return containsCondition(column: "message", value: value, chip: "Message contains \(value)", source: source)
  }

  private static func containsCondition(column: String, value: String, chip: String, source: String) -> FilterCondition {
    FilterCondition(
      fragment: "instr(\(column), ?) > 0",
      values: [.text(value)],
      chip: chip,
      source: source
    )
  }

  private static func exactCondition(column: String, value: String, chip: String, source: String) -> FilterCondition {
    FilterCondition(fragment: "\(column) = ?", values: [.text(value)], chip: chip, source: source)
  }

  private static func excludedCondition(column: String, value: String, chip: String, source: String) -> FilterCondition {
    FilterCondition(
      fragment: "(\(column) IS NULL OR \(column) <> ?)",
      values: [.text(value)],
      chip: chip,
      source: source
    )
  }

  private static func levelCondition(op: String, word: String, source: String) -> FilterCondition {
    guard let rank = levelOrder.firstIndex(of: word) else {
      return FilterCondition(fragment: "1 = 0", values: [], chip: "Level: \(word)?", source: source)
    }
    let picked: [String] =
      switch op {
      case ">=": Array(levelOrder[rank...])
      case ">": rank + 1 < levelOrder.count ? Array(levelOrder[(rank + 1)...]) : []
      case "<=": Array(levelOrder[...rank])
      case "<": rank > 0 ? Array(levelOrder[..<rank]) : []
      default: [word]
      }
    if picked.isEmpty {
      return FilterCondition(fragment: "1 = 0", values: [], chip: "Level: none", source: source)
    }
    let markers = picked.lazy.map { _ in "?" }.joined(separator: ", ")
    return FilterCondition(
      fragment: "level IN (\(markers))",
      values: picked.map { .text($0) },
      chip: "Level: \(picked.joined(separator: ", "))",
      source: source
    )
  }

  private static func timeCondition(bound: String, lower: Bool, source: String) -> FilterCondition? {
    guard let milliseconds = milliseconds(sinceEpoch: bound) else {
      return nil
    }
    let comparison = lower ? ">=" : "<="
    let chip = lower ? "After \(bound)" : "Before \(bound)"
    return FilterCondition(
      fragment: "recorded_at_ms \(comparison) ?",
      values: [.integer(milliseconds)],
      chip: chip,
      source: source
    )
  }

  private static func milliseconds(sinceEpoch bound: String) -> Int64? {
    let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"]
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    for format in formats {
      formatter.dateFormat = format
      if let date = formatter.date(from: bound) {
        return Int64(date.timeIntervalSince1970 * 1000)
      }
    }
    return nil
  }

  private static func payloadCondition(path: String, op: String, value: String, source: String) -> FilterCondition {
    let dotted = path.replacing("[]", with: "[*]")
    let reader = "json_extract_string(payload_json, '$.\(dotted)')"
    switch op {
    case "=":
      if path.contains("[]") {
        let quoted = "\"" + value.replacing("'", with: "") + "\""
        return FilterCondition(
          fragment: "instr(\(reader), ?) > 0",
          values: [.text(quoted)],
          chip: "\(path) is \(value)",
          source: source
        )
      }
      return FilterCondition(
        fragment: "\(reader) = ?",
        values: [.text(value)],
        chip: "\(path) is \(value)",
        source: source
      )

    case "!=":
      return FilterCondition(
        fragment: "(\(reader) IS NULL OR \(reader) <> ?)",
        values: [.text(value)],
        chip: "\(path) is not \(value)",
        source: source
      )

    default:
      return FilterCondition(
        fragment: "instr(\(reader), ?) > 0",
        values: [.text(value)],
        chip: "\(path) contains \(value)",
        source: source
      )
    }
  }

}
