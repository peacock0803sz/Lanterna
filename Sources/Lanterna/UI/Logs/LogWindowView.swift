import SwiftUI

// MARK: - LogWindowView

/// The log window's contents: the toolbar, the table and the status bar.
struct LogWindowView: View {

  // MARK: Internal

  @Bindable var state: LogWindowState

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      LogTable(state: state)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Lanterna Logs")
          .font(.system(size: 13, weight: .bold))
          .accessibilityAddTraits(.isHeader)
        LiveIndicator()
      }
      Spacer(minLength: 12)
    }
    .padding(.leading, 84)
    .padding(.trailing, 14)
    .frame(height: 52)
    .background(.bar)
  }

}

// MARK: - LiveIndicator

/// Whether new lines are being added as they arrive.
struct LiveIndicator: View {
  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(Color(nsColor: .systemGreen))
        .frame(width: 6, height: 6)
        .accessibilityHidden(true)
      Text("Live")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}
