import Foundation

// MARK: - Log Query Matching

/// Splits a query row on whitespace outside quotes, matching the
/// translator so rewrites and display filtering agree.
func splitLogQueryTokens(_ text: String) -> [String] {
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

/// The key before the operator in one token, if the token carries one.
func logQueryKey(of token: String) -> String? {
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
            return String(key)
          }
          return nil
        }
      }
    }
    index = token.index(after: index)
  }
  return nil
}

/// Whether every token besides the listed ones matches the row.
/// The toolbar range already applies its own mirrored tokens as
/// bounds, so those stay out here to avoid double filtering. A
/// hand-typed time bound is not among them and filters the row
/// like a picker bound does.
func matchesQuery(_ row: DiagnosticRow, text: String, excluding: Set<String>) -> Bool {
  for token in splitLogQueryTokens(text) {
    if excluding.contains(token) {
      continue
    }
    if !matchesLogQueryToken(row, token: token) {
      return false
    }
  }
  return true
}

private let logLevelOrder = ["debug", "info", "warning", "error"]

private func matchesLogQueryToken(_ row: DiagnosticRow, token: String) -> Bool {
  let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
  guard let split = splitLogQueryOperator(in: token) else {
    return row.message.contains(bare)
  }
  let rawKey = String(split.key)
  let key = rawKey.lowercased()
  let rawValue = String(split.value).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
  switch (key, split.op) {
  case ("level", _):
    return matchesLevel(row.level, op: split.op, word: rawValue.lowercased())
  case ("category", ":"),
       ("category", "="),
       ("category", "!="):
    return matchesOptionalText(row.category, op: split.op, value: rawValue)
  case ("message", ":"),
       ("message", "="),
       ("message", "!="):
    return matchesOptionalText(row.message, op: split.op, value: rawValue)
  case ("launch", ":"),
       ("launch", "="),
       ("launch", "!="):
    return matchesOptionalText(row.launchID, op: split.op, value: rawValue)
  case ("version", ":"),
       ("version", "="),
       ("version", "!="):
    return matchesOptionalText(row.buildVersion, op: split.op, value: rawValue)
  case ("after", ":"):
    return matchesTimeBound(row.recordedAtMilliseconds, bound: rawValue, lower: true)
  case ("before", ":"):
    return matchesTimeBound(row.recordedAtMilliseconds, bound: rawValue, lower: false)
  default:
    guard isValidLogPath(rawKey) else {
      return row.message.contains(bare)
    }
    return matchesPayload(row.payloadJSON, path: rawKey, op: split.op, value: rawValue)
  }
}

private func splitLogQueryOperator(in token: String) -> (key: Substring, op: String, value: Substring)? {
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

private func isValidLogPath(_ key: String) -> Bool {
  guard !key.isEmpty, key.count <= 128 else { return false }
  let segments = key.split(separator: ".", omittingEmptySubsequences: false)
  for segment in segments {
    var name = segment
    if name.hasSuffix("[]") {
      name = name.dropLast(2)
    }
    guard !name.isEmpty, name.count <= 64 else { return false }
    guard let first = name.first, first.isLetter || first == "_" else { return false }
    guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return false }
  }
  return true
}

private func matchesLevel(_ level: String, op: String, word: String) -> Bool {
  let canonical = word == "warn" ? "warning" : word
  guard let rank = logLevelOrder.firstIndex(of: canonical) else { return false }
  let current = level.lowercased()
  switch op {
  case ">=":
    guard let currentRank = logLevelOrder.firstIndex(of: current) else { return false }
    return currentRank >= rank

  case ">":
    guard let currentRank = logLevelOrder.firstIndex(of: current) else { return false }
    return currentRank > rank

  case "<=":
    guard let currentRank = logLevelOrder.firstIndex(of: current) else { return false }
    return currentRank <= rank

  case "<":
    guard let currentRank = logLevelOrder.firstIndex(of: current) else { return false }
    return currentRank < rank

  case "!=":
    return current != canonical

  default:
    return current == canonical
  }
}

private func matchesOptionalText(_ field: String?, op: String, value: String) -> Bool {
  switch op {
  case "=":
    return field == value
  case "!=":
    return field == nil || field != value
  default:
    guard let field else { return false }
    return field.contains(value)
  }
}

private func matchesTimeBound(_ milliseconds: Int64, bound: String, lower: Bool) -> Bool {
  guard let limit = logBoundMilliseconds(bound) else { return false }
  return lower ? milliseconds >= limit : milliseconds <= limit
}

private func logBoundMilliseconds(_ bound: String) -> Int64? {
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

private func matchesPayload(_ text: String?, path: String, op: String, value: String) -> Bool {
  let values = payloadStrings(text, path: path)
  switch op {
  case "=":
    return values.contains(value)

  case "!=":
    if values.isEmpty {
      return true
    }
    return !values.contains(value)

  default:
    return values.contains { $0.contains(value) }
  }
}

private func payloadStrings(_ text: String?, path: String) -> [String] {
  guard
    let text, let data = text.data(using: .utf8),
    let root = try? JSONSerialization.jsonObject(with: data)
  else { return [] }
  var current: [Any] = [root]
  let segments = path.split(separator: ".").map(String.init)
  for segment in segments {
    var next = [Any]()
    if segment.hasSuffix("[]") {
      let name = String(segment.dropLast(2))
      for item in current {
        guard let dict = item as? [String: Any], let array = dict[name] as? [Any] else { continue }
        next.append(contentsOf: array)
      }
    } else {
      for item in current {
        if let dict = item as? [String: Any], let found = dict[segment] {
          next.append(found)
        } else if let array = item as? [Any] {
          for element in array {
            if let dict = element as? [String: Any], let found = dict[segment] {
              next.append(found)
            }
          }
        }
      }
    }
    current = next
  }
  return current.compactMap { value in
    if let text = value as? String {
      return text
    }
    if let number = value as? NSNumber {
      return number.stringValue
    }
    return nil
  }
}
