import SwiftUI

/// Content of the switcher panel: a compact list of windows.
///
/// The view fills the frame the hosting panel gives it, so `PanelMetrics` is
/// consulted for row height and vertical padding only; the panel owns the
/// overall size.
struct SwitcherView: View {
    let windows: [WindowItem]

    /// The first entry is selected and the selection never moves: this view has
    /// no navigation. An empty list has no selection at all.
    var selectedID: WindowItem.ID? {
        windows.first?.id
    }

    var body: some View {
        List {
            ForEach(windows) { window in
                WindowRow(window: window, isSelected: window.id == selectedID)
                    // Vertical insets and separators are removed so the List
                    // adds nothing to WindowRow's fixed height; the horizontal
                    // insets stay.
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
