import Foundation
import Logging

// MARK: - Logger Metadata grouping

extension Logger.Metadata {
  /// The grouping word the caller attached under the shared key,
  /// if any. Kept out of the emitted line and read by the views.
  var category: String? {
    guard case .string(let word) = self["category"] else {
      return nil
    }
    return word
  }

  /// The attached context as JSON text, keeping nested keys and
  /// arrays. Absent when nothing was attached.
  var payloadJSON: String? {
    guard !isEmpty else {
      return nil
    }
    return "{\(map { "\($0.key.jsonQuoted):\($0.value.jsonText)" }.joined(separator: ","))}"
  }
}

extension Logger.MetadataValue {
  /// Renders one metadata value as JSON text. Convertible values
  /// read through their description, so every shape survives.
  fileprivate var jsonText: String {
    switch self {
    case .string(let text):
      text.jsonQuoted
    case .stringConvertible(let convertible):
      convertible.description.jsonQuoted
    case .array(let values):
      "[\(values.map(\.jsonText).joined(separator: ","))]"
    case .dictionary(let pairs):
      "{\(pairs.lazy.map { "\($0.key.jsonQuoted):\($0.value.jsonText)" }.joined(separator: ","))}"
    }
  }
}

extension String {
  /// Quotes one string for JSON, escaping what JSON forbids raw.
  fileprivate var jsonQuoted: String {
    var out = "\""
    for scalar in unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case Unicode.Scalar(0x08): out += "\\b"
      case Unicode.Scalar(0x0C): out += "\\f"
      default:
        if scalar.value < 0x20 {
          out += String(format: "\\u%04x", scalar.value)
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    out += "\""
    return out
  }
}
