import Foundation

// MARK: - DatabaseStatementCheck

/// Decides whether a database-mode statement may run. Only reads
/// pass: writes are refused outright, and statements that never
/// mention `ts_ms` are refused. Mentioning the column is all it
/// asks; the statement itself decides whether that bounds anything.
/// The row cap is the executor's, applied around the statement.
enum DatabaseStatementCheck {

  // MARK: Internal

  /// The outcome: run the effective text, or show the refusal.
  struct Verdict: Equatable, Sendable {
    var allowed: Bool
    var refusal: String?
    var effectiveText: String
  }

  /// Checks one statement, dropping a trailing semicolon.
  static func check(_ text: String) -> Verdict {
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
    return Verdict(allowed: true, refusal: nil, effectiveText: base)
  }

  /// The bare words of a statement outside every parenthesis,
  /// lowercased, leaving out string literals, quoted names, and
  /// comments, so a subquery's clauses never read as the
  /// statement's own.
  static func topLevelWords(in text: String) -> [String] {
    scan(Array(text)).topLevelWords
  }

  // MARK: Private

  private struct Scan {
    var words: [String]
    /// The words found outside every parenthesis.
    var topLevelWords: [String]
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
    var topLevelWords = [String]()
    var semicolons = [Int]()
    var codeEnd = 0
    var depth = 0
    var balanced = true
    var current = ""
    var index = 0
    func flush() {
      if !current.isEmpty {
        words.append(current.lowercased())
        if depth == 0 {
          topLevelWords.append(current.lowercased())
        }
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
    return Scan(
      words: words,
      topLevelWords: topLevelWords,
      semicolons: semicolons,
      codeEnd: codeEnd,
      balanced: balanced && depth == 0
    )
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

}
