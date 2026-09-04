import SwiftUI

/// Content of the switcher panel: a compact list of windows.
///
/// The view fills the frame the hosting panel gives it, so `PanelMetrics` is
/// consulted for row height only; the panel owns the overall size.
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
        .adaptiveGlass()
    }
}
