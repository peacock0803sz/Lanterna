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

  /// Starts a fresh row: lightweight and empty.
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
/// executor inlines these with quoting, so a typed value never
/// reaches the statement unquoted. The one piece of caller text
/// spliced in as is, a payload path, passes the path check first.
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
/// `after:` and `before:` bound the recorded time. Any other key
/// that reads as a path, dotted or not, reads the payload, with
/// `[]` matching any array element. A token without an operator,
/// or whose key is no valid path, searches the message.
enum LightweightFilter {

  // MARK: Internal

  /// Parses one row. Malformed level comparisons and unreadable
  /// time bounds match nothing rather than searching the message,
  /// so the empty result stays explainable by its chip.
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
    case ("launch", ":"):
      return containsCondition(column: "launch_id", value: rawValue, chip: "Launch: \(rawValue)", source: token)
    case ("launch", "="):
      return exactCondition(column: "launch_id", value: rawValue, chip: "Launch is \(rawValue)", source: token)
    case ("launch", "!="):
      return excludedCondition(column: "launch_id", value: rawValue, chip: "Launch is not \(rawValue)", source: token)
    case ("version", ":"):
      return containsCondition(column: "build_version", value: rawValue, chip: "Version: \(rawValue)", source: token)
    case ("version", "="):
      return exactCondition(column: "build_version", value: rawValue, chip: "Version is \(rawValue)", source: token)
    case ("version", "!="):
      return excludedCondition(column: "build_version", value: rawValue, chip: "Version is not \(rawValue)", source: token)
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

  private static func timeCondition(bound: String, lower: Bool, source: String) -> FilterCondition {
    guard let milliseconds = milliseconds(sinceEpoch: bound) else {
      let chip = lower ? "After \(bound)?" : "Before \(bound)?"
      return FilterCondition(fragment: "1 = 0", values: [], chip: chip, source: source)
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
    if path.contains("[]") {
      return arrayPayloadCondition(path: path, reader: reader, op: op, value: value, source: source)
    }
    switch op {
    case "=":
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

  /// A path through `[]` reads back a list of every element's value,
  /// so the comparison runs per element: any element matching, or
  /// none for the excluded form. A missing payload reads as no
  /// elements.
  private static func arrayPayloadCondition(
    path: String,
    reader: String,
    op: String,
    value: String,
    source: String
  ) -> FilterCondition {
    switch op {
    case "=":
      FilterCondition(
        fragment: "coalesce(list_contains(\(reader), ?), false)",
        values: [.text(value)],
        chip: "\(path) is \(value)",
        source: source
      )

    case "!=":
      FilterCondition(
        fragment: "NOT coalesce(list_contains(\(reader), ?), false)",
        values: [.text(value)],
        chip: "\(path) is not \(value)",
        source: source
      )

    default:
      FilterCondition(
        fragment: "coalesce(len(list_filter(\(reader), element -> instr(element, ?) > 0)) > 0, false)",
        values: [.text(value)],
        chip: "\(path) contains \(value)",
        source: source
      )
    }
  }

}

// MARK: - DatabaseStatementCheck

/// Decides whether a database-mode statement may run. Only reads
/// pass: writes are refused outright, statements that never
/// mention `ts_ms` are refused, and a missing row cap is filled in.
/// Mentioning the column is all it asks; the statement itself
/// decides whether that bounds anything.
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
    let characters = Array(trimmed)
    let scanned = scan(characters)
    guard scanned.balanced else {
      return Verdict(
        allowed: false,
        refusal: "Close every quote, comment, and parenthesis.",
        effectiveText: text
      )
    }
    guard scanned.words.first == "select" || scanned.words.first == "with" else {
      return Verdict(allowed: false, refusal: "SQL mode is read-only.", effectiveText: text)
    }
    if scanned.words.contains(where: forbidden.contains) {
      return Verdict(allowed: false, refusal: "SQL mode is read-only.", effectiveText: text)
    }
    let trailingSemicolon = scanned.semicolons == [scanned.codeEnd - 1]
    if scanned.semicolons.count > 1 || (scanned.semicolons.count == 1 && !trailingSemicolon) {
      return Verdict(allowed: false, refusal: "Run one statement at a time.", effectiveText: text)
    }
    if !scanned.words.contains("ts_ms") {
      return Verdict(
        allowed: false,
        refusal: "SQL needs a time bound (after/before on ts_ms).",
        effectiveText: text
      )
    }
    let base = trailingSemicolon ? String(characters[..<(scanned.codeEnd - 1)]) : trimmed
    if hasRowCap(words: scanned.words) {
      return Verdict(allowed: true, refusal: nil, effectiveText: base)
    }
    // On its own line, so a trailing line comment cannot swallow it.
    return Verdict(allowed: true, refusal: nil, effectiveText: base + "\nLIMIT \(rowLimit)")
  }

  /// The bare words of a statement, lowercased, leaving out string
  /// literals, quoted names, and comments.
  static func words(in text: String) -> [String] {
    scan(Array(text)).words
  }

  // MARK: Private

  private struct Scan {
    var words: [String]
    /// Offsets of the statement separators outside literals and comments.
    var semicolons: [Int]
    /// Just past the last character that is neither blank nor comment.
    var codeEnd: Int
    /// Whether every literal and comment closes and every parenthesis
    /// pairs up, so the statement cannot reach past a wrapper around it.
    var balanced: Bool
  }

  private static let forbidden: Set = [
    "insert",
    "into",
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

  /// Reads the statement the way the database lexer does, so a
  /// quoted word like 'delete me' never reads as a statement and a
  /// quote inside a comment never hides the words after it. Line
  /// and nested block comments, doubled-quote escapes, backslash
  /// escapes in `E'…'`, and `$tag$…$tag$` bodies are all skipped.
  private static func scan(_ characters: [Character]) -> Scan {
    var words = [String]()
    var semicolons = [Int]()
    var codeEnd = 0
    var depth = 0
    var balanced = true
    var current = ""
    var index = 0
    func flush() {
      if !current.isEmpty {
        words.append(current.lowercased())
        current = ""
      }
    }
    func next(_ offset: Int = 1) -> Character? {
      index + offset < characters.count ? characters[index + offset] : nil
    }
    while index < characters.count {
      let character = characters[index]
      if character == "-", next() == "-" {
        flush()
        while index < characters.count, characters[index] != "\n", characters[index] != "\r" {
          index += 1
        }
        continue
      }
      if character == "/", next() == "*" {
        flush()
        guard let end = blockCommentEnd(in: characters, from: index) else {
          balanced = false
          break
        }
        index = end
        continue
      }
      if character == "'" || character == "\"" || character == "`" {
        let escaped = character == "'" && current.lowercased() == "e"
        if escaped {
          current = ""
        } else {
          flush()
        }
        guard let end = quoteEnd(in: characters, from: index, backslashEscapes: escaped) else {
          balanced = false
          break
        }
        index = end
        codeEnd = end
        continue
      }
      if character == "$", current.isEmpty, let tag = dollarTag(in: characters, at: index) {
        guard let end = dollarBodyEnd(in: characters, tag: tag, from: index + tag.count) else {
          balanced = false
          break
        }
        index = end
        codeEnd = end
        continue
      }
      if !character.isWhitespace {
        codeEnd = index + 1
      }
      if character == ";" {
        flush()
        semicolons.append(index)
      } else if character == "(" {
        flush()
        depth += 1
      } else if character == ")" {
        flush()
        depth -= 1
        if depth < 0 {
          balanced = false
        }
      } else if character.isLetter || character.isNumber || character == "_" || (character == "$" && !current.isEmpty) {
        current.append(character)
      } else {
        flush()
      }
      index += 1
    }
    flush()
    return Scan(words: words, semicolons: semicolons, codeEnd: codeEnd, balanced: balanced && depth == 0)
  }

  /// Just past the `*/` closing the comment opened at `start`,
  /// counting nested openings; nil when it never closes.
  private static func blockCommentEnd(in characters: [Character], from start: Int) -> Int? {
    var depth = 0
    var index = start
    while index + 1 < characters.count {
      if characters[index] == "/", characters[index + 1] == "*" {
        depth += 1
        index += 2
      } else if characters[index] == "*", characters[index + 1] == "/" {
        depth -= 1
        index += 2
        if depth == 0 {
          return index
        }
      } else {
        index += 1
      }
    }
    return nil
  }

  /// Just past the quote closing the one at `start`; nil when it
  /// never closes.
  private static func quoteEnd(in characters: [Character], from start: Int, backslashEscapes: Bool) -> Int? {
    let open = characters[start]
    var index = start + 1
    while index < characters.count {
      let character = characters[index]
      if backslashEscapes, character == "\\" {
        index += 2
        continue
      }
      if character == open {
        if index + 1 < characters.count, characters[index + 1] == open {
          index += 2
          continue
        }
        return index + 1
      }
      index += 1
    }
    return nil
  }

  /// The `$tag$` opening a dollar-quoted body at `start`, if one
  /// does. A `$` followed by digits is a parameter instead.
  private static func dollarTag(in characters: [Character], at start: Int) -> [Character]? {
    var index = start + 1
    while index < characters.count {
      let character = characters[index]
      if character == "$" {
        return Array(characters[start...index])
      }
      let allowed = character.isLetter || character == "_" || (index > start + 1 && character.isNumber)
      guard allowed else {
        return nil
      }
      index += 1
    }
    return nil
  }

  /// Just past the tag closing a dollar-quoted body; nil when it
  /// never closes.
  private static func dollarBodyEnd(in characters: [Character], tag: [Character], from start: Int) -> Int? {
    var index = start
    while index + tag.count <= characters.count {
      if characters[index..<(index + tag.count)].elementsEqual(tag) {
        return index + tag.count
      }
      index += 1
    }
    return nil
  }

  private static func hasRowCap(words: [String]) -> Bool {
    zip(words, words.dropFirst()).contains { $0 == "limit" && Int($1) != nil }
  }

}
