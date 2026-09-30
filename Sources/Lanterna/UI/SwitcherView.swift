import SwiftUI

/// Content of the switcher panel: a compact list of windows.
///
/// The view fills the frame the hosting panel gives it, so `PanelMetrics` is
/// consulted for row height and vertical padding only; the panel owns the
/// overall size.
struct SwitcherView: View {

  // MARK: Internal

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
  /// The query narrowing the list, drawn in the query row while filtering
  /// is on. Empty shows its guidance wording instead of drawing nothing.
  var query: String

  /// Whether the query row belongs on screen. Off draws no chrome,
  /// whatever the query reads.
  var filterActive: Bool

  /// A small failure note, drawn under the list. Nil draws nothing and
  /// takes no height.
  var notice: String?

  /// How the special kinds show, read at launch from the config file.
  var modes = DisplayModes.defaults

  /// The compiled exclusion rules, read beside the modes.
  var exclusionRules = [ExclusionRule]()

  /// Whether subsequence queries match as well as substrings, read
  /// beside the modes.
  var fuzzyMatchEnabled = true

  /// The text and icon scale step, handed down from the panel.
  var textScale = TextScaleLevel.standard

  var body: some View {
    // The query row stacks over the list while filtering is on, so the first
    // rows keep their order while the panel grows down from its top edge.
    // The row shows the query beside its match count, whatever the query reads.
    VStack(spacing: 0) {
      if filterActive {
        HStack {
          Image(systemName: "magnifyingglass")
            .font(.system(size: scaled(18)))
            .foregroundStyle(.secondary)
          if query.isEmpty {
            Text("Type to filter")
              .font(.system(size: scaled(20)))
              .foregroundStyle(.tertiary)
          } else {
            Text(query)
              .font(.system(size: scaled(20)))
              .foregroundStyle(.primary)
          }
          Spacer(minLength: 0)
          Text(countWording)
            .font(.system(size: scaled(12)))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        Divider()
          .padding(.horizontal, 12)
      }
      ScrollViewReader { proxy in
        List {
          ForEach(ordinaryRows) { window in
            row(window)
          }
          if !subgroupRows.isEmpty {
            ForEach(subgroupRows, id: \.0) { subgroup, rows in
              Text(heading(for: subgroup).uppercased())
                .font(.system(size: scaled(11), weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: PanelMetrics.rowHeight(for: textScale))
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
              ForEach(rows) { window in
                row(window, isInSubgroup: true)
              }
            }
          }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, PanelMetrics.rowHeight(for: textScale))
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
          .font(.system(size: scaled(11)))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.top, 4)
      }
    }
    // The glass covers the whole stack, not the list alone: the query row
    // above it would otherwise float over the desktop with no background
    // to read against. An inactive panel stacks nothing, so it draws
    // exactly as it did before.
    .padding(.vertical, PanelMetrics.verticalPadding)
    .adaptiveGlass(cornerRadius: 16)
  }

  /// The query row count wording for one split of the list. It counts the
  /// window rows the list draws, ordinary and subgrouped alike, and not the
  /// heading rows, unlike `PanelMetrics.drawnRowCount`. Singular for one
  /// row and plural otherwise.
  static func countWording(
    ordinary: [WindowItem],
    subgroups: [(DisplaySubgroup, [WindowItem])]
  ) -> String {
    let count = ordinary.count + subgroups.reduce(0) { $0 + $1.1.count }
    return count == 1 ? "1 window" : "\(count) windows"
  }

  // MARK: Private

  /// The query row count wording for the rows on screen.
  private var countWording: String {
    Self.countWording(ordinary: ordinaryRows, subgroups: subgroupRows)
  }

  /// The ordinary rows, drawing first and in the order they arrived.
  private var ordinaryRows: [WindowItem] {
    sections.ordinary
  }

  /// The non-empty subgroups below the ordinary rows, in drawing order.
  private var subgroupRows: [(DisplaySubgroup, [WindowItem])] {
    sections.subgroups
  }

  /// The list split for drawing. The rows arrive in the order the filter
  /// hands the choice (`DisplayModes.displayOrdered`), and splitting keeps
  /// each row's place within its section, so the rows draw in the order
  /// the arrows step through them. Never re-ranks here: the rows arrive
  /// pre-ordered from the filter, and ranking twice would drop the
  /// remembered row from its section front.
  private var sections: (ordinary: [WindowItem], subgroups: [(DisplaySubgroup, [WindowItem])]) {
    DisplayModes.sections(
      of: windows,
      modes: modes,
      query: query,
      exclusions: exclusionRules,
      fuzzy: fuzzyMatchEnabled,
      ordering: .mru
    )
  }

  /// One scaled point size: the base size times the step, in whole points.
  private func scaled(_ base: Double) -> Double {
    (base * textScale.factor).rounded()
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

  private func row(_ window: WindowItem, isInSubgroup: Bool = false) -> some View {
    WindowRow(
      window: window,
      isSelected: window.id == selectedID,
      query: query,
      fuzzy: fuzzyMatchEnabled,
      textScale: textScale,
      isInSubgroup: isInSubgroup
    )
    // Vertical insets and separators are removed so the List
    // adds nothing to WindowRow's fixed height; the horizontal
    // insets stay.
    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
    .listRowSeparator(.hidden)
    .listRowBackground(Color.clear)
    .id(window.id)
  }

}
