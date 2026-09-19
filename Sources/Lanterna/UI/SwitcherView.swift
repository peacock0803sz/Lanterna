import SwiftUI

/// Content of the switcher panel: a compact list of windows.
///
/// The view fills the frame the hosting panel gives it, so `PanelMetrics` is
/// consulted for row height and vertical padding only; the panel owns the
/// overall size.
struct SwitcherView: View {
    let windows: [WindowItem]

    /// Which row to draw as chosen, decided elsewhere and handed in.
    ///
    /// It used to be worked out here, as the first row of whatever list
    /// arrived, and that agreed with what the presenter thought only because
    /// nothing could move the choice. Two derivations of one thing are two
    /// things that can disagree, and a keyboard that moves the selection is
    /// exactly what makes them.
    ///
    /// No default value on purpose. An optional gets none in the memberwise
    /// initialiser unless one is written, so every place that builds this
    /// view has to say what is chosen — including the one that swaps a new
    /// list in, which would otherwise take `nil` and clear the highlight
    /// without a word.
    var selectedID: WindowItem.Identifier?

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
