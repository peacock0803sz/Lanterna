import AppKit
import SwiftUI

// MARK: - FieldsSidebar

/// Counts beside the table for the rows on screen.
///
/// Each section folds with its disclosure. Picking a value adds
/// it as a filter chip, while holding Option excludes it
/// instead. Launches and versions beyond the time range stay
/// listed but dimmed, so an empty count still reads as outside
/// rather than missing.
struct FieldsSidebar: View {

  // MARK: Internal

  var visibleRows: [DiagnosticRow]
  var allRows: [DiagnosticRow]
  var isEnabled = true
  var onApply: (String) -> Void = { _ in }
  var onExclude: (String) -> Void = { _ in }
  var onClose: () -> Void = { }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          section(title: "Level", values: levelCounts, outside: [], token: levelToken, excludeToken: levelExcludeToken)
          section(
            title: "Category",
            values: categoryCounts,
            outside: [],
            token: categoryToken,
            excludeToken: categoryExcludeToken
          )
          section(
            title: "Launch",
            values: launchCounts,
            outside: outsideLaunches,
            token: launchToken,
            excludeToken: launchExcludeToken
          )
          section(
            title: "source.version",
            values: versionCounts,
            outside: outsideVersions,
            token: versionToken,
            excludeToken: versionExcludeToken
          )
          section(title: "app.name", values: appNameCounts, outside: [], token: appNameToken, excludeToken: appNameExcludeToken)
          section(
            title: "attempts.result",
            values: attemptResultCounts,
            outside: [],
            token: attemptResultToken,
            excludeToken: attemptResultExcludeToken
          )
        }
        .padding(10)
      }
      hint
    }
    .frame(minWidth: 190, maxWidth: 240)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Fields sidebar")
  }

  // MARK: Private

  @State private var collapsed = Set<String>()

  private var header: some View {
    HStack {
      Text("Fields")
        .font(.headline)
        .accessibilityLabel("Fields")
      Spacer()
      Text("in \(visibleRows.count) shown")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Scope in \(visibleRows.count) shown")
      Button {
        onClose()
      } label: {
        Image(systemName: "sidebar.left")
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Hide Fields sidebar")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
  }

  private var hint: some View {
    Text("Click a value to filter · ⌥-click to exclude")
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(10)
      .accessibilityLabel("Click a value to filter with option-click to exclude")
  }

  private var levelCounts: [(value: String, count: Int)] {
    counted(visibleRows.map { $0.level })
  }

  private var categoryCounts: [(value: String, count: Int)] {
    counted(visibleRows.map { $0.category ?? "—" })
  }

  private var launchCounts: [(value: String, count: Int)] {
    counted(visibleRows.map { $0.launchID ?? "current" })
  }

  private var outsideLaunches: [(value: String, count: Int)] {
    let visibleKeys = Set(visibleRows.map { $0.launchID ?? "current" })
    let allKeys = Set(allRows.map { $0.launchID ?? "current" })
    return allKeys.subtracting(visibleKeys).sorted().map { ($0, 0) }
  }

  private var versionCounts: [(value: String, count: Int)] {
    counted(visibleRows.compactMap { $0.buildVersion })
  }

  private var outsideVersions: [(value: String, count: Int)] {
    let visibleKeys = Set(visibleRows.compactMap { $0.buildVersion })
    let allKeys = Set(allRows.compactMap { $0.buildVersion })
    return allKeys.subtracting(visibleKeys).sorted().map { ($0, 0) }
  }

  private var appNameCounts: [(value: String, count: Int)] {
    counted(visibleRows.compactMap { payloadValue($0.payloadJSON, path: ["app", "name"]) })
  }

  private var attemptResultCounts: [(value: String, count: Int)] {
    counted(visibleRows.flatMap { payloadArrayValues($0.payloadJSON, key: "attempts", field: "result") })
  }

  private func section(
    title: String,
    values: [(value: String, count: Int)],
    outside: [(value: String, count: Int)],
    token: @escaping (String) -> String,
    excludeToken: @escaping (String) -> String
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        if collapsed.contains(title) {
          collapsed.remove(title)
        } else {
          collapsed.insert(title)
        }
      } label: {
        HStack(spacing: 4) {
          Text(collapsed.contains(title) ? "▸" : "▾")
          Text(title)
            .fontWeight(.semibold)
        }
        .font(.callout)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(title) section, \(collapsed.contains(title) ? "collapsed" : "expanded")")
      if !collapsed.contains(title) {
        ForEach(values, id: \.value) { entry in
          valueRow(value: entry.value, count: entry.count, dimmed: false, token: token, excludeToken: excludeToken)
        }
        ForEach(outside, id: \.value) { entry in
          valueRow(value: entry.value, count: entry.count, dimmed: true, token: token, excludeToken: excludeToken)
        }
      }
    }
  }

  private func valueRow(
    value: String,
    count: Int,
    dimmed: Bool,
    token: @escaping (String) -> String,
    excludeToken: @escaping (String) -> String
  ) -> some View {
    Button {
      if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
        onExclude(excludeToken(value))
      } else {
        onApply(token(value))
      }
    } label: {
      HStack {
        Text(value)
          .font(.callout)
          .lineLimit(1)
        Spacer()
        Text("\(count)")
          .font(.callout.monospaced())
          .foregroundStyle(.secondary)
      }
      .opacity(dimmed ? 0.4 : 1)
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityLabel("\(value), \(count) entries\(dimmed ? ", outside range" : "")")
    .accessibilityHint("Click to filter, Option-click to exclude")
  }

  private func counted(_ values: [String]) -> [(value: String, count: Int)] {
    var tallies = [String: Int]()
    for value in values {
      tallies[value, default: 0] += 1
    }
    return tallies.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
  }

  private func payloadValue(_ text: String?, path: [String]) -> String? {
    guard
      let text, let data = text.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    var current: Any? = root
    for key in path {
      guard let dict = current as? [String: Any] else {
        return nil
      }
      current = dict[key]
    }
    return current as? String
  }

  private func payloadArrayValues(_ text: String?, key: String, field: String) -> [String] {
    guard
      let text, let data = text.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let items = root[key] as? [[String: Any]]
    else {
      return []
    }
    return items.compactMap { $0[field] as? String }
  }

  private func levelToken(_ value: String) -> String {
    "level=\(value)"
  }

  private func levelExcludeToken(_ value: String) -> String {
    "level!=\(value)"
  }

  private func categoryToken(_ value: String) -> String {
    value == "—" ? "" : "category:\(value)"
  }

  private func categoryExcludeToken(_ value: String) -> String {
    value == "—" ? "" : "category!=\(value)"
  }

  private func launchToken(_ value: String) -> String {
    "launch:\(value)"
  }

  private func launchExcludeToken(_ value: String) -> String {
    "launch!=\(value)"
  }

  private func versionToken(_ value: String) -> String {
    "version:\(value)"
  }

  private func versionExcludeToken(_ value: String) -> String {
    "version!=\(value)"
  }

  private func appNameToken(_ value: String) -> String {
    "app.name:\(value)"
  }

  private func appNameExcludeToken(_ value: String) -> String {
    "app.name!=\(value)"
  }

  private func attemptResultToken(_ value: String) -> String {
    "attempts[].result=\(value)"
  }

  private func attemptResultExcludeToken(_ value: String) -> String {
    "attempts[].result!=\(value)"
  }

}
