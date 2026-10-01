import AppKit
import SwiftUI

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

// MARK: - LogDetailSourceLink

/// Builds public source links for a stored row.
///
/// Reads the commit from the recorded build string, so past launches
/// keep pointing at the build that emitted them. Shows plain text when
/// no commit can be read, such as for local uncommitted builds.
enum LogDetailSourceLink {

  // MARK: Internal

  static func commitHash(from buildVersion: String?) -> String? {
    guard
      let raw = buildVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else {
      return nil
    }
    let lowered = raw.lowercased()
    if lowered.contains("dirty") {
      return nil
    }
    if lowered == "dev" {
      return nil
    }
    if let dashRange = raw.range(of: "-g", options: .backwards) {
      let tail = String(raw[dashRange.upperBound...])
      if isHashText(tail) {
        return tail
      }
    }
    let parts = raw.split(separator: "-")
    if let last = parts.last.map(String.init), isHashText(last) {
      return last
    }
    if isHashText(raw) {
      return raw
    }
    if raw.hasPrefix("v"), !raw.contains(" "), !raw.contains("/") {
      return raw
    }
    return nil
  }

  static func splitFileLine(_ text: String) -> (path: String, line: Int?)? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let colon = trimmed.lastIndex(of: ":") else {
      return (cleanPath(trimmed), nil)
    }
    let head = String(trimmed[..<colon])
    let tail = String(trimmed[trimmed.index(after: colon)...])
    let path = cleanPath(head)
    guard !path.isEmpty else { return nil }
    if let number = Int(tail.trimmingCharacters(in: .whitespaces)), number > 0 {
      return (path, number)
    }
    return (cleanPath(trimmed), nil)
  }

  static func url(path: String, line: Int, commit: String) -> URL? {
    URL(string: "https://github.com/peacock0803sz/Lanterna/blob/\(commit)/\(path)#L\(line)")
  }

  // MARK: Private

  private static let seven = 7
  private static let forty = 40

  private static func cleanPath(_ text: String) -> String {
    var path = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while path.hasPrefix("/") {
      path = String(path.dropFirst())
    }
    return path
  }

  private static func isHashText(_ text: String) -> Bool {
    guard text.count >= seven, text.count <= forty else { return false }
    return text.allSatisfy { $0.isHexDigit }
  }

}

// MARK: - LogDetailView

/// Detail pane for one selected row.
///
/// Shows the level badge with the full timestamp and the category,
/// plus the complete message text and the stored fields as a folding
/// tree. The owner shows this view below the list in a resizable split
/// when a single row stays selected, and hides it when the selection
/// clears. Closing through the button or esc only clears the selection,
/// so the list keeps its reading position.
struct LogDetailView: View {

  // MARK: Internal

  var row: DiagnosticRow
  var launchStartMilliseconds: Int64?
  var isCurrentLaunch = false
  var onClose: () -> Void = { }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      head
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          messageBox
          fieldsSection
        }
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Entry Detail")
  }

  // MARK: Private

  @State private var collapsed = Set<String>()

  private var parsedFields: [(key: String, value: DetailValue)] {
    parseDetailPayload(row.payloadJSON)
  }

  private var displayFields: [(key: String, value: DetailValue)] {
    var fields = parsedFields
    if let index = fields.firstIndex(where: { $0.key == "source" }) {
      switch fields[index].value {
      case .object(var pairs):
        if !pairs.contains(where: { $0.key == "version" }), let build = row.buildVersion {
          pairs.append(("version", .string(build)))
          fields[index] = ("source", .object(pairs))
        }

      case .array,
           .string,
           .number,
           .boolean,
           .none:
        break
      }
    }
    let topVersion = fields.contains { $0.key == "version" }
    let sourceVersion = fields.contains {
      guard $0.key == "source" else { return false }
      guard case .object(let pairs) = $0.value else { return false }
      return pairs.contains { $0.key == "version" }
    }
    if !topVersion, !sourceVersion, let build = row.buildVersion {
      fields.append(("version", .string(build)))
    }
    return fields
  }

  private var commitForRow: String? {
    LogDetailSourceLink.commitHash(from: row.buildVersion)
  }

  private var head: some View {
    HStack(spacing: 10) {
      LogLevelBadge(level: row.level)
      Text(LogExport.fullTime(milliseconds: row.recordedAtMilliseconds))
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .accessibilityLabel("Full time \(LogExport.fullTime(milliseconds: row.recordedAtMilliseconds))")
      Text(row.category ?? "—")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .accessibilityLabel("Category \(row.category ?? "no category")")
      Spacer()
      Button {
        onClose()
      } label: {
        Image(systemName: "xmark")
          .font(.callout)
          .frame(width: 22, height: 22)
          .background(.quaternary.opacity(0.5))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Close detail")
      .accessibilityHint("Clears the row selection and closes the detail")
    }
  }

  private var messageBox: some View {
    Text(row.message)
      .font(.system(.body, design: .monospaced))
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .accessibilityLabel("Full message")
  }

  private var fieldsSection: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 12) {
        Text("Fields")
          .font(.callout)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
          .accessibilityLabel("Fields")
        Spacer()
        Button("Expand All") {
          collapsed.removeAll()
        }
        .font(.callout)
        .accessibilityLabel("Expand All")
        Button("Collapse All") {
          collapsed = allContainerPaths()
        }
        .font(.callout)
        .accessibilityLabel("Collapse All")
      }
      .padding(.bottom, 4)
      launchRow
      ForEach(displayFields, id: \.key) { entry in
        nodeView(path: entry.key, key: entry.key, value: entry.value, depth: 0)
      }
    }
  }

  private var launchRow: some View {
    HStack(spacing: 4) {
      Color.clear
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
      Text("launch")
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 150, alignment: .leading)
      Text(launchSummary)
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 1)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("launch \(launchSummary)")
  }

  private var launchSummary: String {
    let marker = isCurrentLaunch ? "this launch" : "past launch"
    if let start = launchStartMilliseconds {
      let stamp = String(LogExport.fullTime(milliseconds: start).prefix(19))
      return "\(stamp) (\(marker)) · entry #\(row.sequence)"
    }
    let key = row.launchID ?? "current"
    return "\(key) (\(marker)) · entry #\(row.sequence)"
  }

  private func nodeView(path: String, key: String, value: DetailValue, depth: Int) -> AnyView {
    AnyView(nodeContent(path: path, key: key, value: value, depth: depth))
  }

  private func nodeContent(path: String, key: String, value: DetailValue, depth: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 4) {
        if value.isContainer {
          Button {
            if collapsed.contains(path) {
              collapsed.remove(path)
            } else {
              collapsed.insert(path)
            }
          } label: {
            Text(collapsed.contains(path) ? "▸" : "▾")
              .font(.callout)
              .foregroundStyle(.secondary)
              .frame(width: 12, height: 12)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(key) \(collapsed.contains(path) ? "collapsed" : "expanded")")
        } else {
          Color.clear
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
        }
        Text(key)
          .font(.system(.callout, design: .monospaced))
          .foregroundStyle(value.isContainer ? .primary : .secondary)
          .fontWeight(value.isContainer ? .semibold : .regular)
          .frame(width: 150, alignment: .leading)
          .textSelection(.enabled)
        if value.isContainer {
          if collapsed.contains(path) {
            Text(collapsedDetailSummary(for: value))
              .font(.system(.callout, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            Text(arrayCountHint(for: value))
              .font(.system(.callout, design: .monospaced))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        } else if isVersionRow(path: path, key: key) {
          Text(row.buildVersion ?? leafDetailText(for: value))
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let link = sourceLink(path: path, key: key, value: value) {
          Button {
            NSWorkspace.shared.open(link.url)
          } label: {
            HStack(spacing: 4) {
              Text(link.display)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.blue)
              Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.blue)
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Open source \(link.display) in browser")
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Text(leafDetailText(for: value))
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.vertical, 1)
      .padding(.leading, CGFloat(depth) * 16)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(accessibilityText(path: path, key: key, value: value))
      if value.isContainer, !collapsed.contains(path) {
        switch value {
        case .object(let pairs):
          ForEach(pairs, id: \.key) { child in
            nodeView(path: "\(path).\(child.key)", key: child.key, value: child.value, depth: depth + 1)
          }

        case .array(let items):
          ForEach(items.indices, id: \.self) { index in
            nodeView(
              path: "\(path)[\(index)]",
              key: "\(index)",
              value: items[index],
              depth: depth + 1
            )
          }

        case .string,
             .number,
             .boolean,
             .none:
          EmptyView()
        }
      }
    }
  }

  private func arrayCountHint(for value: DetailValue) -> String {
    switch value {
    case .array(let items) where !items.isEmpty:
      "[\(items.count)]"
    case .object,
         .array,
         .string,
         .number,
         .boolean,
         .none:
      ""
    }
  }

  private func accessibilityText(path: String, key: String, value: DetailValue) -> String {
    if value.isContainer {
      let state = collapsed.contains(path) ? "collapsed" : "expanded"
      let summary = collapsed.contains(path) ? collapsedDetailSummary(for: value) : "\(value.childCount) children"
      return "\(key) \(summary) \(state)"
    }
    if isVersionRow(path: path, key: key) {
      return "\(key) \(row.buildVersion ?? leafDetailText(for: value))"
    }
    if let link = sourceLink(path: path, key: key, value: value) {
      return "\(key) \(link.display) link"
    }
    return "\(key) \(leafDetailText(for: value))"
  }

  private func isVersionRow(path: String, key: String) -> Bool {
    guard key == "version" else { return false }
    return path == "version" || path == "source.version" || path.hasSuffix(".version")
  }

  private func isSourceFileRow(path: String, key: String, value: DetailValue) -> Bool {
    guard key == "file" || key == "path" else { return false }
    guard case .string = value else { return false }
    return path.lowercased().contains("source")
  }

  private func sourceLink(path: String, key: String, value: DetailValue) -> (display: String, url: URL)? {
    guard isSourceFileRow(path: path, key: key, value: value) else { return nil }
    guard case .string(let text) = value else { return nil }
    guard let split = LogDetailSourceLink.splitFileLine(text) else { return nil }
    guard let line = split.line else { return nil }
    guard let commit = commitForRow else { return nil }
    guard let url = LogDetailSourceLink.url(path: split.path, line: line, commit: commit) else { return nil }
    return ("\(split.path):\(line)", url)
  }

  private func allContainerPaths() -> Set<String> {
    var out = Set<String>()
    for entry in displayFields {
      collectContainerPaths(path: entry.key, value: entry.value, into: &out)
    }
    return out
  }

  private func collectContainerPaths(path: String, value: DetailValue, into out: inout Set<String>) {
    guard value.isContainer else { return }
    out.insert(path)
    switch value {
    case .object(let pairs):
      for child in pairs {
        collectContainerPaths(path: "\(path).\(child.key)", value: child.value, into: &out)
      }

    case .array(let items):
      for index in items.indices {
        collectContainerPaths(path: "\(path)[\(index)]", value: items[index], into: &out)
      }

    case .string,
         .number,
         .boolean,
         .none:
      break
    }
  }

}
