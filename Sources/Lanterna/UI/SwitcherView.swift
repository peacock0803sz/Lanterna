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

    /// A small failure note, drawn under the list. Nil draws nothing and
    /// takes no height.
    var notice: String?

    /// How the special kinds show, read at launch from the config file.
    var modes: DisplayModes = .defaults

    /// The ordinary rows, drawing first and in the order they arrived.
    private var ordinaryRows: [WindowItem] {
        sections.ordinary
    }

    /// The non-empty subgroups below the separator, in drawing order.
    private var subgroupRows: [(DisplaySubgroup, [WindowItem])] {
        sections.subgroups
    }

    /// The list split for drawing. The rows arrive in the order the filter
    /// hands the choice (`DisplayModes.displayOrdered`), and splitting keeps
    /// each row's place within its section, so the rows draw in the order
    /// the arrows step through them.
    private var sections: (ordinary: [WindowItem], subgroups: [(DisplaySubgroup, [WindowItem])]) {
        DisplayModes.sections(of: windows, modes: modes, query: query)
    }

    /// The heading over one subgroup, in plain words.
    private func heading(for subgroup: DisplaySubgroup) -> String {
        switch subgroup {
        case .otherSpace:
            "Other Spaces"
        case .hiddenApp:
            "Hidden Apps"
        case .minimized:
            "Minimized"
        case .fullscreen:
            "Fullscreen"
        }
    }

    private func row(_ window: WindowItem) -> some View {
        WindowRow(window: window, isSelected: window.id == selectedID, query: query)
            // Vertical insets and separators are removed so the List
            // adds nothing to WindowRow's fixed height; the horizontal
            // insets stay.
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .id(window.id)
    }

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
                    ForEach(ordinaryRows) { window in
                        row(window)
                    }
                    if !subgroupRows.isEmpty {
                        if !ordinaryRows.isEmpty {
                            Divider()
                                // A row like the others, on every OS: without an
                                // explicit height the list's default decides, and
                                // that default is not the same on every macOS.
                                .frame(height: PanelMetrics.rowHeight)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(subgroupRows, id: \.0) { subgroup, rows in
                            Text(heading(for: subgroup))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(height: PanelMetrics.rowHeight)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            ForEach(rows) { window in
                                row(window)
                            }
                        }
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
            if let notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
        // The glass covers the whole stack, not the list alone: the query
        // and the header above it would otherwise float over the desktop
        // with no background to read against. An inactive panel stacks
        // nothing, so it draws exactly as it did before.
        .padding(.vertical, PanelMetrics.verticalPadding)
        .adaptiveGlass()
    }
}
