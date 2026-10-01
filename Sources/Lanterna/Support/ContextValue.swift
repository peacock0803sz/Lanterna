import Foundation

// MARK: - ContextValue

/// One value attached to a diagnostics line.
///
/// Flat on purpose: no nesting and no arrays, so every key can become a
/// column and every value reads on one line.
enum ContextValue: Equatable, Sendable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)

  // MARK: Internal

  /// The value as a person reads it in a column or the detail pane.
  var displayText: String {
    switch self {
    case .string(let value): value
    case .int(let value): String(value)
    case .double(let value): String(value)
    case .bool(let value): value ? "true" : "false"
    }
  }

  /// The value as a JSON literal: strings quoted and escaped, numbers and
  /// booleans bare. A double that JSON cannot carry (NaN, infinity) is
  /// written as a string so the line stays parseable.
  var jsonLiteral: String {
    switch self {
    case .string(let value): Self.jsonString(value)
    case .int(let value): String(value)
    case .double(let value): value.isFinite ? String(value) : Self.jsonString(String(value))
    case .bool(let value): value ? "true" : "false"
    }
  }

  /// A JSON string literal for `text`.
  ///
  /// Escaped by hand rather than through `JSONEncoder`: the saved log
  /// writes a line under the lock the hotkey paths share, and building an
  /// encoder per string costs more than the escaping itself. JSON asks for
  /// the quote, the backslash and the control characters to be escaped,
  /// and nothing else.
  static func jsonString(_ text: String) -> String {
    var literal = "\""
    literal.reserveCapacity(text.utf8.count + 2)
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": literal += "\\\""
      case "\\": literal += "\\\\"
      case "\n": literal += "\\n"
      case "\r": literal += "\\r"
      case "\t": literal += "\\t"
      case "\u{08}": literal += "\\b"
      case "\u{0C}": literal += "\\f"
      case "\u{00}" ... "\u{1F}": literal += String(format: "\\u%04x", scalar.value)
      default: literal.unicodeScalars.append(scalar)
      }
    }
    literal += "\""
    return literal
  }

  /// A JSON object for `context`, keys in name order so two lines with the
  /// same keys read the same.
  static func jsonObject(_ context: [String: ContextValue]) -> String {
    let members = context.sorted { $0.key < $1.key }.map { key, value in
      "\(jsonString(key)):\(value.jsonLiteral)"
    }
    return "{\(members.joined(separator: ","))}"
  }
}

// MARK: - ContextBox

/// Carries a line's context through swift-log's metadata without losing the
/// value types.
///
/// swift-log's metadata values are strings, lists, dictionaries or a
/// string-convertible. Wrapping the whole context in one string-convertible
/// lets the handler take it back out as typed values; anything else that
/// arrives is read through its description.
struct ContextBox: CustomStringConvertible, Sendable {
  let values: [String: ContextValue]

  var description: String {
    ContextValue.jsonObject(values)
  }
}
