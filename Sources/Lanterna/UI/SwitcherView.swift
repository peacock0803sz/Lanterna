import SwiftUI

/// Content of the switcher panel: a compact list of windows.
struct SwitcherView: View {
    let windows: [WindowItem]

    /// Selection is fixed at the first entry for now; an empty list has none.
    private var selectedID: WindowItem.ID? {
        windows.first?.id
    }

    var body: some View {
        List {
            ForEach(windows) { window in
                WindowRow(window: window, isSelected: window.id == selectedID)
                    // Zero vertical insets and no separators keep each row at
                    // exactly PanelMetrics.rowHeight.
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, PanelMetrics.rowHeight)
        .scrollContentBackground(.hidden)
        .padding(.vertical, PanelMetrics.verticalPadding)
        .frame(
            width: PanelMetrics.width,
            height: PanelMetrics.height(rowCount: windows.count)
        )
        .adaptiveGlass()
    }
}
