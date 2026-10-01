import Foundation

// MARK: - DetailValue

/// One decoded payload value for the detail tree.
enum DetailValue {
  case object([(key: String, value: DetailValue)])
  case array([DetailValue])
  case string(String)
  case number(String)
  case boolean(Bool)
  case none

  // MARK: Internal

  var isContainer: Bool {
    switch self {
    case .object,
         .array:
      true
    case .string,
         .number,
         .boolean,
         .none:
      false
    }
  }

  var childCount: Int {
    switch self {
    case .object(let pairs):
      pairs.count
    case .array(let items):
      items.count
    case .string,
         .number,
         .boolean,
         .none:
      0
    }
  }
}

// MARK: - DetailParsing

/// Turns stored JSON text into a tree the detail pane can fold.
func parseDetailPayload(_ text: String?) -> [(key: String, value: DetailValue)] {
  guard
    let text,
    let data = text.data(using: .utf8),
    let root = try? JSONSerialization.jsonObject(with: data)
  else {
    return []
  }
  guard let dict = root as? [String: Any] else {
    return []
  }
  let preferred = ["app", "window", "space", "display", "attempts", "source"]
  var ordered = [(key: String, value: DetailValue)]()
  for key in preferred {
    if let found = dict[key] {
      ordered.append((key, detailValue(from: found)))
    }
  }
  let rest = dict.keys.filter { !preferred.contains($0) }.sorted().map { key in
    (key, detailValue(from: dict[key] as Any))
  }
  ordered.append(contentsOf: rest)
  return ordered
}

/// Converts one decoded JSON fragment into a tree value.
func detailValue(from fragment: Any) -> DetailValue {
  if let dict = fragment as? [String: Any] {
    let pairs = dict.keys.sorted().map { key in
      (key, detailValue(from: dict[key] as Any))
    }
    return .object(pairs)
  }
  if let items = fragment as? [Any] {
    return .array(items.map { detailValue(from: $0) })
  }
  if let text = fragment as? String {
    return .string(text)
  }
  if let flag = fragment as? Bool {
    return .boolean(flag)
  }
  if let number = fragment as? NSNumber {
    return .number(number.stringValue)
  }
  if fragment is NSNull {
    return .none
  }
  return .string(String(describing: fragment))
}

/// One line summary shown while a node stays folded.
func collapsedDetailSummary(for value: DetailValue) -> String {
  switch value {
  case .object(let pairs):
    return "{\(pairs.count) items}"

  case .array(let items):
    return "[\(items.count) entries]"

  case .string(let text):
    let lead = String(text.prefix(40))
    return text.count > lead.count ? lead + "…" : lead

  case .number:
    return "number"

  case .boolean:
    return "boolean"

  case .none:
    return "null"
  }
}

/// Plain reading of a leaf for display and assistive labels.
func leafDetailText(for value: DetailValue) -> String {
  switch value {
  case .object,
       .array:
    ""
  case .string(let text):
    text
  case .number(let text):
    text
  case .boolean(let flag):
    flag ? "true" : "false"
  case .none:
    "null"
  }
}
