import AppKit
import Foundation
import SwiftUI

// MARK: - LogWindowView

/// The log contents with live tail and export.
struct LogWindowView: View {

  // MARK: Internal

  @ObservedObject var state: LogWindowState

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      toolbar
      QueryBarView(
        query: $state.query,
        queryFocused: $queryFocused,
        onCommit: { state.refresh() },
        onModeSwitchRequest: requestModeSwitch,
        timeLabel: state.timeLabel,
        pendingFilteredCount: state.pendingCount,
        isPaused: state.isPaused,
        onRemoveChip: { state.removeChip($0) },
        onClearAll: { state.clearQuery() },
        onResumeFiltered: { state.togglePause() }
      )
      HStack(alignment: .top, spacing: 0) {
        if state.isSidebarShown {
          FieldsSidebar(
            visibleRows: state.flatVisibleRows,
            allRows: state.allKeptRows,
            isEnabled: isLightweight,
            onApply: { state.addQueryToken($0) },
            onExclude: { state.addQueryToken($0) },
            onClose: { state.setSidebarShown(false) }
          )
          Divider()
        }
        VStack(spacing: 0) {
          HistogramView(
            filteredRows: state.flatVisibleRows,
            totalRows: state.allKeptRows,
            launchCount: max(state.allKeptLaunchCount, state.launchCount),
            selectedRowID: state.selection.first,
            isCompact: !state.selection.isEmpty,
            isCollapsed: $state.isHistogramCollapsed,
            isFilteringEnabled: isLightweight,
            onJumpToMilliseconds: { state.jump(toMilliseconds: $0) },
            onShowInterval: { state.showInterval(startMilliseconds: $0, endMilliseconds: $1) },
            onShowLaunch: { state.showLaunch($0) },
            onResetTime: { state.resetTime() },
            onCopyInterval: { state.copyInterval(startMilliseconds: $0, endMilliseconds: $1) },
            onOpenJumpDialog: { },
            oldestKeptDay: state.oldestKeptDay,
            onJumpToDate: { state.jump(to: $0) }
          )
          .onChange(of: state.isHistogramCollapsed) { _, next in
            state.setHistogramCollapsed(next)
          }
          if VersionLogWindow.clearMarkerMilliseconds != nil {
            clearBanner
          }
          if state.afterRangeCount > 0 {
            afterRangeBanner
          }
          if state.flatVisibleRows.isEmpty {
            emptyView
          } else if let detailRow = selectedDetailRow {
            VSplitView {
              LogTableView(
                sections: state.sections,
                selection: $state.selection,
                autoScroll: state.autoScroll,
                jumpTargetID: state.jumpTargetID
              )
              .frame(minHeight: 120, maxHeight: .infinity)
              LogDetailView(
                row: detailRow,
                launchStartMilliseconds: selectedDetailLaunchStart,
                isCurrentLaunch: selectedDetailIsCurrent,
                onClose: { state.selection.removeAll() }
              )
              .frame(minHeight: 160, maxHeight: .infinity)
            }
          } else {
            LogTableView(
              sections: state.sections,
              selection: $state.selection,
              autoScroll: state.autoScroll,
              jumpTargetID: state.jumpTargetID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      LogStatusBar(
        visibleCount: state.visibleCount,
        totalCount: state.totalCount,
        launchCount: max(state.allKeptLaunchCount, state.launchCount),
        selectedCount: state.selection.count,
        timeLabel: state.timeLabel,
        isPaused: state.isPaused,
        isFiltered: state.isFiltering,
        showsDetail: selectedDetailRow != nil,
        autoScroll: $state.autoScroll
      )
    }
    .frame(minWidth: 640, minHeight: 420)
    .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
      state.refresh()
    }
    .background(closeDetailShortcut)
    .alert("Switch query mode?", isPresented: $showSwitchConfirm, presenting: pendingMode) { mode in
      Button("Switch", role: .destructive) {
        state.query.mode = mode
        state.query.lightweightText = ""
        state.query.databaseText = ""
        state.refresh()
        pendingMode = nil
      }
      Button("Cancel", role: .cancel) {
        pendingMode = nil
      }
    } message: { _ in
      Text("The current conditions will be discarded.")
    }
  }

  // MARK: Private

  @FocusState private var queryFocused: Bool
  @State private var showTimePopover = false
  @State private var pendingMode: LogQuery.Mode?
  @State private var showSwitchConfirm = false

  private var isLightweight: Bool {
    state.query.mode == .lightweight
  }

  private var selectedDetailRow: DiagnosticRow? {
    guard state.selection.count == 1, let wanted = state.selection.first else { return nil }
    return state.flatVisibleRows.first { $0.rowID == wanted }
  }

  private var selectedDetailLaunchStart: Int64? {
    guard let row = selectedDetailRow else { return nil }
    let key = row.launchID
    for section in state.sections {
      if section.launchID == key {
        return Int64(section.startMilliseconds)
      }
    }
    return nil
  }

  private var selectedDetailIsCurrent: Bool {
    guard let row = selectedDetailRow else { return false }
    let key = row.launchID
    for section in state.sections where section.launchID == key {
      return section.isCurrent
    }
    return false
  }

  private var toolbar: some View {
    HStack(spacing: 10) {
      Text(state.liveLabel)
        .font(.subheadline)
        .fontWeight(.medium)
        .accessibilityLabel(state.liveLabel)
      Button {
        state.setSidebarShown(!state.isSidebarShown)
      } label: {
        Image(systemName: "sidebar.left")
      }
      .buttonStyle(.plain)
      .accessibilityLabel(state.isSidebarShown ? "Hide Fields sidebar" : "Show Fields sidebar")
      Menu("Level") {
        Button("All levels") { state.setLevelFilter(nil) }
        Divider()
        Button("Errors only") { state.setLevelFilter("level=error") }
        Button("Warnings and errors") { state.setLevelFilter("level>=warn") }
        Button("Info and above") { state.setLevelFilter("level>=info") }
      }
      .disabled(!isLightweight)
      .accessibilityLabel("Level filter")
      Menu("Category") {
        Button("All categories") { state.setCategoryFilter(nil) }
        Divider()
        ForEach(state.availableCategories, id: \.value) { entry in
          Button("\(entry.value) (\(entry.count))") {
            state.setCategoryFilter("category:\(entry.value)")
          }
        }
      }
      .disabled(!isLightweight)
      .accessibilityLabel("Category filter")
      Menu("Launch") {
        Button("All launches") { state.setLaunchFilter(nil) }
        Divider()
        ForEach(state.availableLaunches, id: \.value) { entry in
          Button(launchMenuTitle(for: entry)) {
            state.setLaunchFilter("launch:\(entry.value)")
          }
        }
      }
      .disabled(!isLightweight)
      .accessibilityLabel("Launch filter")
      Button(state.timeLabel) {
        showTimePopover = true
      }
      .disabled(!isLightweight)
      .accessibilityLabel("Time range \(state.timeLabel)")
      .popover(isPresented: $showTimePopover) {
        TimeRangeView(
          selection: $state.timeSelection,
          launchStart: nil,
          onApply: { selection in
            state.applyTimeSelection(selection)
            showTimePopover = false
          },
          onReset: {
            state.resetTime()
            showTimePopover = false
          }
        )
      }
      Spacer()
      if !state.isDefaultTime {
        Button("Show latest") {
          state.showLatest()
        }
        .accessibilityLabel("Show latest")
      }
      Button(state.isPaused ? "Resume" : "Pause") {
        state.togglePause()
      }
      .keyboardShortcut("p", modifiers: .command)
      .accessibilityLabel(state.isPaused ? "Resume live tail" : "Pause live tail")
      Button("Copy") {
        state.copyText()
      }
      .keyboardShortcut("c", modifiers: .command)
      .accessibilityLabel("Copy selected rows as text")
      Button("Copy JSON") {
        state.copyJSON()
      }
      .keyboardShortcut("c", modifiers: [.command, .option])
      .accessibilityLabel("Copy selected rows as JSON Lines")
      Button("Export") {
        state.exportFile()
      }
      .accessibilityLabel("Export visible rows to a file")
      Button("Clear") {
        state.clearView()
      }
      .accessibilityLabel("Clear visible entries")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }

  private var clearBanner: some View {
    Text("Cleared — earlier entries hidden until relaunch")
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .accessibilityLabel("Cleared, earlier entries hidden until relaunch")
  }

  private var afterRangeBanner: some View {
    HStack {
      Text("\(state.afterRangeCount) new after range · Show latest")
      Button("Show latest") {
        state.showLatest()
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .accessibilityLabel("\(state.afterRangeCount) new after range, show latest")
  }

  private var emptyView: some View {
    VStack(spacing: 8) {
      Spacer()
      if state.totalCount == 0 {
        Text("No log entries yet")
          .font(.body)
          .foregroundStyle(.secondary)
          .accessibilityLabel("No log entries yet")
      } else {
        Text("No entries match the current filters")
          .font(.body)
          .foregroundStyle(.secondary)
          .accessibilityLabel("No entries match the current filters")
        if isLightweight {
          Button("Clear All") {
            state.clearQuery()
          }
          .accessibilityLabel("Clear All filters")
        }
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      state.totalCount == 0 ? "No log entries yet" : "No entries match the current filters"
    )
  }

  private var closeDetailShortcut: some View {
    Button("Close detail") {
      state.selection.removeAll()
    }
    .keyboardShortcut(.cancelAction)
    .hidden()
    .accessibilityLabel("Close detail")
    .accessibilityHint("Clears the row selection and closes the detail")
  }

  private func requestModeSwitch(_ next: LogQuery.Mode) {
    guard next != state.query.mode else { return }
    let current = state.query.activeText.trimmingCharacters(in: .whitespacesAndNewlines)
    if current.isEmpty {
      state.query.mode = next
      state.refresh()
    } else {
      pendingMode = next
      showSwitchConfirm = true
    }
  }

  private func launchMenuTitle(for entry: (value: String, count: Int, isCurrent: Bool)) -> String {
    if entry.isCurrent {
      return "This launch (\(entry.count))"
    }
    let short = entry.value.prefix(8)
    return "\(short) (\(entry.count))"
  }

}

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

/// Whether every token besides the time bounds matches the row.
/// Time bounds stay with the toolbar range, so the query text can
/// mirror them for chips without double filtering here.
func matchesQueryExcludingTime(_ row: DiagnosticRow, text: String) -> Bool {
  for token in splitLogQueryTokens(text) {
    if let key = logQueryKey(of: token)?.lowercased(), key == "after" || key == "before" {
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
