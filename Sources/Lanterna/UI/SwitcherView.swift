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
    var selectedID: WindowItem.Identifier?

    /// Which appearance this list belongs to, counted up by the panel.
    ///
    /// A reused panel keeps its scrolled position across appearances, so a
    /// second appearance opens wherever the last one left off while the
    /// choice is back on the first row — chosen but off screen. The choice
    /// alone cannot always say that: an appearance that never moves it
    /// leaves `selectedID` unchanged and `.onChange(of:)` silent. A token
    /// that moves every time does the saying instead.
    var appearanceToken: Int

    /// Every call site passes the choice explicitly: an omitted choice
    /// would quietly draw no row as chosen, which is exactly what the one
    /// place swapping a new list in must never do. `nil` is only for when
    /// nothing is chosen.
    ///
    /// The query narrowing the list, drawn large over it. Empty draws
    /// nothing: an appearance that never narrows looks exactly as it did
    /// before any of this existed.
    var query: String

    /// Whether the filter chrome (the query when it reads anything, and the
    /// header) belongs on screen. Off draws neither, whatever the query is.
    var filterActive: Bool

    var body: some View {
        // The query and the header stack over the list, so the first rows
        // keep their order while the panel grows down from its top edge.
        // Empty draws nothing at all, and a panel without the filter draws
        // no chrome either, so either looks exactly as it did before any of
        // this existed.
        VStack(spacing: 0) {
            if filterActive, !query.isEmpty {
                Text(query)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            if filterActive {
                Text("All Results")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            ScrollViewReader { proxy in
                List {
                    ForEach(windows) { window in
                        WindowRow(window: window, isSelected: window.id == selectedID, query: query)
                            // Vertical insets and separators are removed so the List
                            // adds nothing to WindowRow's fixed height; the horizontal
                            // insets stay.
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .id(window.id)
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, PanelMetrics.rowHeight)
                .scrollContentBackground(.hidden)
                // The panel is never the place typing goes, so it must never
                // draw the ring that says it is. What is not added here matters
                // as much: a `List(selection:)` binding would hand the arrow
                // keys to the list ahead of the panel, and `.allowsHitTesting`
                // turned off would take wheel and trackpad scrolling with it —
                // the one way to reach the far rows of a long list.
                .focusEffectDisabled(true)
                .padding(.vertical, PanelMetrics.verticalPadding)
                .adaptiveGlass()
                // The least scrolling that shows the row, and nothing when it is
                // already showing. `.center` would move on every keystroke, and
                // a list that jumps under a choice being moved along it is one
                // the eye has to find again each time.
                .onChange(of: selectedID) { _, id in
                    if let id {
                        proxy.scrollTo(id, anchor: nil)
                    }
                }
                // A new appearance always moves the token, even when the choice
                // is the same row it was last time, so reopening onto the first
                // row scrolls back to it rather than staying where the last
                // appearance left off.
                .onChange(of: appearanceToken) { _, _ in
                    if let id = selectedID {
                        proxy.scrollTo(id, anchor: nil)
                    }
                }
            }
        }
    }
}
