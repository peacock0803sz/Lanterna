import SwiftUI

/// The log window's contents: the toolbar, the table and the status bar.
struct LogWindowView: View {

  // MARK: Internal

  @Bindable var state: LogWindowState

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      if state.isPaused {
        PausedBar(pendingCount: state.pendingCount, resume: state.resume)
        Divider()
      }
      LogTable(state: state)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
          if !state.canCopyOrExport {
            LogEmptyState(isFiltering: state.isFiltering)
              .background(.background)
          }
        }
      Divider()
      LogStatusBar(
        totalCount: state.entryCount,
        shownCount: state.shownEntryCount,
        selectedCount: state.selectedCount,
        isFiltered: false,
        isLoading: false
      )
    }
    .frame(minWidth: 640, minHeight: 360)
  }

  // MARK: Private

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
