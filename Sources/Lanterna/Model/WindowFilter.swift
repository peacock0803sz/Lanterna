import Foundation

/// Narrowing the list on screen by what the user typed, and nothing else.
///
/// A namespace rather than a type with state: matching is a pure function of
/// the query and the list, so every row of the contract below can be held to
/// without a window server, a clock, or a panel. The state the narrowing
/// keeps between keystrokes (the query and what was chosen when it vanished)
/// belongs to `FilterState`, not here.
enum WindowFilter {

  // MARK: Internal

  /// The text one row is judged by: app name, one space, window title.
  static func combinedText(of item: WindowItem) -> String {
    item.appName + " " + item.windowTitle
  }

  /// Whether the query's characters appear in the target in order, gaps
  /// allowed. Case-insensitive. An empty query answers false; callers
  /// return the whole list without judging.
  static func matchesSubsequence(query: String, target: String) -> Bool {
    !subsequenceRanges(query: query, in: target).isEmpty
  }

  /// The rows ordered for score mode, keeping the input order otherwise.
  ///
  /// Contiguous matches, through the engine when it is open, come before
  /// scattered subsequence matches; among those, an earlier match start
  /// comes first. Ties keep
  /// the order they arrived in (a stable sort through the index), so
  /// equal rows never change places. An empty query changes nothing.
  static func scoreOrdered(_ rows: [WindowItem], query: String, engine: MigemoEngine) -> [WindowItem] {
    rows.enumerated().map { entry in
      let target = combinedText(of: entry.element)
      return (offset: entry.offset, quality: matchQuality(query: query, target: target, engine: engine), element: entry.element)
    }.sorted { left, right in
      if left.quality != right.quality {
        return left.quality < right.quality
      }
      return left.offset < right.offset
    }.map(\.element)
  }

  /// Where each query character matched, in order, for highlighting.
  ///
  /// Case-insensitive, and empty when the query never appears in order.
  /// Ranges never overlap: searching resumes past each match. An empty
  /// query matches nothing.
  static func subsequenceRanges(query: String, in text: String) -> [Range<String.Index>] {
    guard !query.isEmpty else { return [] }
    var ranges = [Range<String.Index>]()
    var remainder = text.startIndex ..< text.endIndex
    for character in query {
      guard let found = text.range(of: String(character), options: .caseInsensitive, range: remainder) else {
        return []
      }
      ranges.append(found)
      remainder = found.upperBound ..< text.endIndex
    }
    return ranges
  }

  /// Every range where the query occurs in the text, for highlighting.
  ///
  /// Case-insensitive, and every occurrence rather than only the first.
  /// Ranges never overlap: searching resumes past each match. An empty
  /// query matches nothing.
  static func matchedRanges(query: String, in text: String) -> [Range<String.Index>] {
    guard !query.isEmpty else { return [] }
    var ranges = [Range<String.Index>]()
    var remainder = text.startIndex ..< text.endIndex
    while let found = text.range(of: query, options: .caseInsensitive, range: remainder) {
      ranges.append(found)
      remainder = found.upperBound ..< text.endIndex
    }
    return ranges
  }

  /// The rows matching the query, in the order they arrived.
  ///
  /// Filtering keeps the order; it never sorts, so the MRU order the list
  /// arrived in survives the narrowing. An empty query returns the input
  /// unchanged, judging not one row, which is what keeps the show path
  /// free of measurable work. One pattern per query decides every row; a
  /// closed engine falls back to a case-insensitive substring match. With
  /// fuzzy on a subsequence match counts too, so fuzzy never narrows.
  static func matching(
    _ query: String,
    against windows: [WindowItem],
    engine: MigemoEngine,
    fuzzy: Bool = false
  ) -> [WindowItem] {
    guard !query.isEmpty else { return windows }
    return windows.filter {
      let target = combinedText(of: $0)
      return matches(query: query, target: target, engine: engine)
        || (fuzzy && matchesSubsequence(query: query, target: target))
    }
  }

  /// The ranges a row highlights: the contiguous matches, or under fuzzy
  /// each query character in order when nothing matched contiguously.
  static func highlightRanges(
    query: String,
    in text: String,
    engine: MigemoEngine,
    fuzzy: Bool
  ) -> [Range<String.Index>] {
    let contiguous = matchedRanges(query: query, in: text, engine: engine)
    return contiguous.isEmpty && fuzzy ? subsequenceRanges(query: query, in: text) : contiguous
  }

  /// Whether one row matches a romaji query through the engine.
  static func matches(query: String, target: String, engine: MigemoEngine) -> Bool {
    guard !query.isEmpty else { return true }
    return !matchedRanges(query: query, in: target, engine: engine).isEmpty
  }

  /// Every range where a romaji query matches, for highlighting.
  ///
  /// Ranges cover the whole matched span on the target side, whose
  /// length need not equal the query's. A query no pattern can parse
  /// falls back to a literal match and never fails the filter.
  static func matchedRanges(query: String, in text: String, engine: MigemoEngine) -> [Range<String.Index>] {
    guard !query.isEmpty else { return [] }
    if engine.isOpen {
      if let regex = engine.regex(for: query) {
        return ranges(of: regex, in: text)
      }
      if let literal = regexRanges(pattern: MigemoEngine.escapedLiteral(query), in: text) {
        return literal
      }
    }
    return matchedRanges(query: query, in: text)
  }

  /// Whether the string a keystroke produced joins the query, and as what.
  ///
  /// Judged by content alone, because origin cannot be told apart this far
  /// down: a confirmed string and a directly typed one arrive as the same
  /// characters. One ASCII character joins only when alphanumeric; anything
  /// longer, or holding non-ASCII, is taken verbatim as a confirmed string.
  /// A single private-use scalar types nothing: that is how the function
  /// keys arrive, arrows included, and letting one through would both block
  /// its bare binding and narrow the list on it.
  static func allowedText(_ text: String) -> String? {
    guard !text.isEmpty else { return nil }
    guard text.count == 1, let scalar = text.unicodeScalars.first else {
      return text
    }
    if isPrivateUse(scalar.value) {
      return nil
    }
    guard scalar.isASCII else {
      return text
    }
    return isASCIILetterOrDigit(scalar.value) ? text : nil
  }

  // MARK: Private

  /// How one row ranks: contiguous matches before scattered ones, then
  /// by where the match starts. Rows no matcher judges rank last.
  private static func matchQuality(query: String, target: String, engine: MigemoEngine) -> (contiguous: Int, start: Int) {
    if let first = matchedRanges(query: query, in: target, engine: engine).first {
      return (0, target.distance(from: target.startIndex, to: first.lowerBound))
    }
    if let first = subsequenceRanges(query: query, in: target).first {
      return (1, target.distance(from: target.startIndex, to: first.lowerBound))
    }
    return (2, Int.max)
  }

  /// The ranges one regular expression matches, or nil when the
  /// pattern itself cannot be read. An empty hit list means no match,
  /// never a broken pattern.
  private static func regexRanges(pattern: String, in text: String) -> [Range<String.Index>]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    return ranges(of: regex, in: text)
  }

  /// Every range one compiled expression matches in the text.
  private static func ranges(of regex: NSRegularExpression, in text: String) -> [Range<String.Index>] {
    let full = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: full).compactMap { Range($0.range, in: text) }
  }

  /// ASCII alphanumerics, without reaching for Foundation.
  private static func isASCIILetterOrDigit(_ value: UInt32) -> Bool {
    switch value {
    case 0x30 ... 0x39,
         0x41 ... 0x5A,
         0x61 ... 0x7A:
      true
    default:
      false
    }
  }

  /// Private-use scalars, where AppKit puts the function keys.
  private static func isPrivateUse(_ value: UInt32) -> Bool {
    switch value {
    case 0xE000 ... 0xF8FF,
         0xF0000 ... 0xFFFFD,
         0x100000 ... 0x10FFFD:
      true
    default:
      false
    }
  }

}
