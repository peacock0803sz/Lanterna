import SwiftUI

/// The log window's contents: the toolbar, the table and the status bar.
struct LogWindowView: View {

  // MARK: Internal

  @Bindable var state: LogWindowState

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      queryBar
      Divider()
      if state.isPaused {
        PausedBar(pendingCount: state.pendingCount, resume: state.resume)
        Divider()
      }
      // One split view whether or not the detail shows, so opening and
      // closing it leaves the table, and where it was scrolled, alone.
      VSplitView {
        LogTable(state: state)
          .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
          .overlay {
            if !state.canCopyOrExport {
              LogEmptyState(isFiltering: state.isFiltering)
                .background(.background)
            }
          }
        if let entry = state.detailEntry {
          LogDetailView(entry: entry, close: { state.selection = [] })
            .frame(minHeight: 140, idealHeight: 260, maxHeight: .infinity)
        }
      }
      Divider()
      LogStatusBar(
        totalCount: state.entryCount,
        shownCount: state.shownEntryCount,
        selectedCount: state.selectedCount,
        isFiltered: state.isFiltering,
        isLoading: state.isLoading
      )
    }
    .frame(minWidth: 640, minHeight: 360)
  }

  // MARK: Private

  /// The search field under the toolbar. Matches message text only.
  private var queryBar: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
      TextField("Search messages", text: $state.searchText)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .accessibilityLabel("Search messages")
      if !state.searchText.isEmpty {
        Button {
          state.searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 8)
    .frame(height: 26)
    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
    .padding(.horizontal, 14)
    .padding(.bottom, 8)
    .background(.bar)
  }

  /// Shares its row with the window's traffic lights, which the window
  /// draws over the leading inset.
  private var toolbar: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Lanterna Logs")
          .font(.system(size: 13, weight: .bold))
          .accessibilityAddTraits(.isHeader)
        LiveIndicator(isPaused: state.isPaused, pendingCount: state.pendingCount)
      }
      Spacer(minLength: 12)
      Picker("Level", selection: $state.levelFloor) {
        ForEach(LevelFloor.allCases, id: \.self) { floor in
          Text(floor.title).tag(floor)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .fixedSize()
      .accessibilityLabel("Level")
      Picker("Category", selection: $state.category) {
        Text("All categories").tag(LogCategory?.none)
        Divider()
        ForEach(LogCategory.allCases.sorted { $0.rawValue < $1.rawValue }, id: \.self) { category in
          Text(category.rawValue).tag(LogCategory?.some(category))
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .fixedSize()
      .accessibilityLabel("Category")
      Picker("Launches", selection: $state.scope) {
        Text(LaunchScope.thisLaunch.title).tag(LaunchScope.thisLaunch)
        Text(LaunchScope.allLaunches.title).tag(LaunchScope.allLaunches)
          .selectionDisabled(!state.hasSavedLogs)
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .fixedSize()
      .accessibilityLabel("Launches")
      Menu {
        LogColumnsMenu(state: state)
      } label: {
        Image(systemName: "tablecells")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("Columns")
      .accessibilityLabel("Columns")
      .padding(.trailing, 6)
      ToolbarIconButton(
        systemImage: state.isPaused ? "play.fill" : "pause.fill",
        label: state.isPaused ? "Resume" : "Pause",
        shortcut: "⌘P",
        isProminent: state.isPaused,
        action: state.togglePause
      )
      .keyboardShortcut("p", modifiers: .command)
      ToolbarIconButton(
        systemImage: "doc.on.doc",
        label: "Copy",
        shortcut: "⌘C",
        action: { state.copy() }
      )
      .keyboardShortcut("c", modifiers: .command)
      .disabled(!state.canCopyOrExport)
      ToolbarIconButton(
        systemImage: "square.and.arrow.up",
        label: "Export…",
        action: { state.exportWithPanel(attachedTo: NSApp.keyWindow) }
      )
      .disabled(!state.canCopyOrExport)
    }
    .padding(.leading, 84)
    .padding(.trailing, 14)
    .frame(height: 52)
    .background(.bar)
  }

}
