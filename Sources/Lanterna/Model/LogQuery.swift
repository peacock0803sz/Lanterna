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
    let rawKey = String(split.key)
    let key = rawKey.lowercased()
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
    case ("message", "="):
      return exactCondition(column: "message", value: rawValue, chip: "Message is \(rawValue)", source: token)
    case ("message", "!="):
      return excludedCondition(column: "message", value: rawValue, chip: "Message is not \(rawValue)", source: token)
    case ("launch", _):
      return exactCondition(column: "launch_id", value: rawValue, chip: "Launch: \(rawValue)", source: token)
    case ("version", _):
      return exactCondition(column: "build_version", value: rawValue, chip: "Version: \(rawValue)", source: token)
    case ("after", ":"):
      return timeCondition(bound: rawValue, lower: true, source: token)
    case ("before", ":"):
      return timeCondition(bound: rawValue, lower: false, source: token)
    default:
      guard isValidPayloadPath(rawKey) else {
        return messageContains(bare, source: token)
      }
      return payloadCondition(path: rawKey, op: split.op, value: rawValue, source: token)
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

  private static func isValidPayloadPath(_ key: String) -> Bool {
    guard !key.isEmpty, key.count <= 128 else {
      return false
    }
    let segments = key.split(separator: ".", omittingEmptySubsequences: false)
    for segment in segments {
      var name = segment
      if name.hasSuffix("[]") {
        name = name.dropLast(2)
      }
      guard !name.isEmpty, name.count <= 64 else {
        return false
      }
      guard let first = name.first, first.isLetter || first == "_" else {
        return false
      }
      guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
        return false
      }
    }
    return true
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
    let canonical = word == "warn" ? "warning" : word
    guard let rank = levelOrder.firstIndex(of: canonical) else {
      return FilterCondition(fragment: "1 = 0", values: [], chip: "Level: \(word)?", source: source)
    }
    let picked: [String] =
      switch op {
      case ">=": Array(levelOrder[rank...])
      case ">": rank + 1 < levelOrder.count ? Array(levelOrder[(rank + 1)...]) : []
      case "<=": Array(levelOrder[...rank])
      case "<": rank > 0 ? Array(levelOrder[..<rank]) : []
      default: [canonical]
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
      fragment: "ts_ms \(comparison) ?",
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
    let reader = "json_extract_string(payload, '$.\(dotted)')"
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

// MARK: - DatabaseStatementCheck

/// Decides whether a database-mode statement may run. Only reads
/// pass: writes are refused outright, statements without a time
/// bound are refused, and a missing row cap is filled in.
enum DatabaseStatementCheck {

  // MARK: Internal

  /// The outcome: run the effective text, or show the refusal.
  struct Verdict: Equatable, Sendable {
    var allowed: Bool
    var refusal: String?
    var effectiveText: String
  }

  /// Checks one statement, filling in the default row cap.
  static func check(_ text: String, rowLimit: Int = 5000) -> Verdict {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return Verdict(allowed: false, refusal: "Enter a statement to run.", effectiveText: text)
    }
    let head = strippedLeadingComments(trimmed).lowercased()
    guard head.hasPrefix("select") || head.hasPrefix("with") else {
      return Verdict(allowed: false, refusal: "SQL mode is read-only.", effectiveText: text)
    }
    let scanned = scan(trimmed)
    if scanned.hasForbiddenWord {
      return Verdict(allowed: false, refusal: "SQL mode is read-only.", effectiveText: text)
    }
    if scanned.semicolons > 1 || (scanned.semicolons == 1 && !trimmed.hasSuffix(";")) {
      return Verdict(allowed: false, refusal: "Run one statement at a time.", effectiveText: text)
    }
    if !scanned.words.contains("ts_ms") {
      return Verdict(
        allowed: false,
        refusal: "SQL needs a time bound (after/before on ts_ms).",
        effectiveText: text
      )
    }
    if hasRowCap(words: scanned.words) {
      return Verdict(allowed: true, refusal: nil, effectiveText: trimmed)
    }
    let base = trimmed.hasSuffix(";") ? String(trimmed.dropLast()) : trimmed
    return Verdict(allowed: true, refusal: nil, effectiveText: base + " LIMIT \(rowLimit)")
  }

  // MARK: Private

  private struct Scan {
    var words: [String]
    var hasForbiddenWord: Bool
    var semicolons: Int
  }

  private static let forbidden: Set = [
    "insert",
    "update",
    "delete",
    "drop",
    "alter",
    "create",
    "attach",
    "detach",
    "copy",
    "install",
    "load",
    "pragma",
    "vacuum",
    "checkpoint",
    "call",
    "transaction",
    "begin",
    "commit",
    "rollback",
    "execute",
  ]

  /// Collects bare words outside string literals, so a quoted
  /// word like 'delete me' never reads as a statement.
  private static func scan(_ text: String) -> Scan {
    var words = [String]()
    var forbidden = false
    var semicolons = 0
    var current = ""
    var quote: Character?
    var index = text.startIndex
    func flush() {
      if !current.isEmpty {
        let word = current.lowercased()
        words.append(word)
        if forbiddenWordsContain(word) {
          forbidden = true
        }
        current = ""
      }
    }
    while index < text.endIndex {
      let character = text[index]
      if let open = quote {
        if character == open {
          let next = text.index(after: index)
          if next < text.endIndex, text[next] == open {
            index = text.index(after: next)
            continue
          }
          quote = nil
        }
      } else if character == "'" || character == "\"" || character == "`" {
        quote = character
      } else if character == ";" {
        flush()
        semicolons += 1
      } else if character.isLetter || character.isNumber || character == "_" {
        current.append(character)
      } else {
        flush()
      }
      index = text.index(after: index)
    }
    flush()
    return Scan(words: words, hasForbiddenWord: forbidden, semicolons: semicolons)
  }

  private static func forbiddenWordsContain(_ word: String) -> Bool {
    forbidden.contains(word)
  }

  private static func hasRowCap(words: [String]) -> Bool {
    zip(words, words.dropFirst()).contains { $0 == "limit" && Int($1) != nil }
  }

  private static func strippedLeadingComments(_ text: String) -> String {
    var rest = text[...]
    while true {
      rest = rest.drop(while: { $0.isWhitespace })
      if rest.hasPrefix("--") {
        rest = rest.drop(while: { $0 != "\n" })
        continue
      }
      if rest.hasPrefix("/*") {
        if let end = rest.range(of: "*/") {
          rest = rest[end.upperBound...]
          continue
        }
        return ""
      }
      break
    }
    return String(rest)
  }

}
