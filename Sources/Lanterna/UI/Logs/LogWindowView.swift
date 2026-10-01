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
        isLoading: state.isLoading,
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

  /// When this launch started, for the Since-this-launch range.
  /// Absent before the first spill, where the range stays open
  /// and shows everything kept.
  private var launchStart: Date? {
    Diagnostics.activeLaunchStartMilliseconds.map { Date(timeIntervalSince1970: Double($0) / 1_000) }
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
        .accessibilityHint(state.levelHint)
        .help(state.levelHint)
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
          launchStart: launchStart,
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
      if let error = state.databaseError {
        Text(error)
          .font(.body)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .accessibilityLabel(error)
      } else if state.totalCount == 0 {
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
      state.databaseError ?? (state.totalCount == 0 ? "No log entries yet" : "No entries match the current filters")
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
