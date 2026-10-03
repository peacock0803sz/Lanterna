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
  ///
  /// Every call site passes the choice explicitly: an omitted choice
  /// would quietly draw no row as chosen, which is exactly what the one
  /// place swapping a new list in must never do. `nil` is only for when
  /// nothing is chosen.
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

  /// The band over a list narrowed to one application. Nil draws nothing
  /// and takes no height.
  var scopeBand: ScopeBand?

  /// How the rows are grouped, read beside the modes.
  var grouping = GroupingPolicy()

  /// Whether hovering a row moves the selection, handed down from
  /// the panel. Off draws no tracking: the rows behave as before.
  var hoverSelect = false

  /// Whether scrolling moves the selection, handed down from the
  /// panel. Off scrolls the view only, as before.
  var scrollSelect = false

  /// The pointer position this appearance opened with. Hovers arriving
  /// where the pointer sat are dropped, so opening under the pointer
  /// leaves the opening choice alone.
  var hoverAnchor: HoverAnchor?

  /// The row order numbers draw in, empty when none show. Carried from
  /// the panel on every swap, so a narrowed list and the numbers move
  /// together and never disagree about which row is which.
  var numberedIDs = [WindowItem.Identifier]()

  /// How the left edge of each row reads. Handed down from the panel,
  /// which freezes it for the appearance, so swaps during the
  /// appearance never pick up a change made while the panel is up.
  var hintsMode = HintsMode.prefix

  /// Where a row hover goes. Called only while the hover switch is on.
  var onHoverRow: ((WindowItem.Identifier) -> Void)?

  /// Where a row click goes. Always called: clicking picks the row and
  /// commits to it whatever the switches say.
  var onClickRow: ((WindowItem.Identifier) -> Void)?

  var body: some View {
    // The query row stacks over the list while filtering is on, so the first
    // rows keep their order while the panel grows down from its top edge.
    // The row shows the query, or guidance wording while it is empty, beside
    // the number of window rows the list draws.
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
      if let scopeBand {
        scopeBandRow(scopeBand)
      }
      ScrollViewReader { proxy in
        List {
          if layout.blocks.isEmpty {
            emptyLine
          }
          ForEach(layout.blocks, id: \.key) { block in
            switch block {
            case .groupHeading(let heading, let order):
              groupHeading(heading, isFirst: order == firstGroupOrder)
            case .subgroupHeading(let subgroup, let group):
              subgroupHeading(subgroup, nested: group != nil)
            case .row(let window, let isInSubgroup):
              row(window, isInSubgroup: isInSubgroup)
            }
          }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, PanelMetrics.rowHeight(for: textScale))
        .scrollContentBackground(.hidden)
        // While the scroll switch is on the list itself does not
        // scroll: wheel amounts turn into selection steps on the panel,
        // and the view follows the choice. Off scrolls the view only,
        // as before.
        .scrollDisabled(scrollSelect)
        // The list scrolls under the choice, but the bar itself stays out of
        // the panel, so the rows read the way the mock reads.
        .scrollIndicators(.never)
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
    // to read against.
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
    return wording(count: count)
  }

  /// The query row count wording for one layout: its window rows, and not
  /// its headings.
  static func countWording(_ layout: PanelLayout) -> String {
    wording(count: layout.windowCount)
  }

  // MARK: Private

  /// The query row count wording for the rows on screen.
  private var countWording: String {
    Self.countWording(layout)
  }

  /// The list as it draws. The rows arrive in the order the filter hands
  /// the choice, and laying them out keeps each row's place within its
  /// section, so the rows draw in the order the arrows step through them.
  /// Never re-ranks here: the rows arrive pre-ordered from the filter, and
  /// ranking twice would drop the remembered row from its section front.
  private var layout: PanelLayout {
    PanelLayout.make(
      rows: windows,
      modes: modes,
      query: query,
      exclusions: exclusionRules,
      fuzzy: fuzzyMatchEnabled,
      ordering: .mru,
      grouping: grouping
    )
  }

  /// The group drawn first, which draws no rule above its heading.
  private var firstGroupOrder: Int? {
    for block in layout.blocks {
      if case .groupHeading(_, let order) = block {
        return order
      }
    }
    return nil
  }

  /// The one line drawn in place of rows when nothing is left to show:
  /// a query matching nothing, an active application with no row, or
  /// every row hidden by the display modes or excluded with no query.
  private var emptyLine: some View {
    Text("No windows")
      .font(.system(size: scaled(13)))
      .foregroundStyle(.tertiary)
      .frame(maxWidth: .infinity, alignment: .center)
      .frame(height: PanelMetrics.rowHeight(for: textScale))
      .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
  }

  private static func wording(count: Int) -> String {
    count == 1 ? "1 window" : "\(count) windows"
  }

  /// The 1-based number one row draws, or nothing when numbers are
  /// down. Positions read off the carried order, so the numbers name
  /// the same rows the choice steps through.
  private func number(for id: WindowItem.Identifier) -> Int? {
    guard let index = numberedIDs.firstIndex(of: id) else { return nil }
    return index + 1
  }

  /// The heading over one group: its number when it has one, its title,
  /// and what tells it apart, at one row's height with a rule above every
  /// group but the first.
  private func groupHeading(_ heading: PanelLayout.GroupHeading, isFirst: Bool) -> some View {
    HStack(spacing: 8) {
      if let number = heading.number {
        Text("\(number)")
          .font(.system(size: scaled(10), weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
          .frame(width: scaled(18), height: scaled(18))
          .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
      }
      Text(heading.title)
        .font(.system(size: scaled(12), weight: .semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .truncationMode(.tail)
      if let detail = heading.detail {
        Text(detail)
          .font(.system(size: scaled(11)))
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .frame(height: PanelMetrics.rowHeight(for: textScale))
    .overlay(alignment: .top) {
      if !isFirst {
        Divider()
      }
    }
    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
    .listRowSeparator(.hidden)
    .listRowBackground(Color.clear)
  }

  /// The band saying the list holds one application's rows, and which key
  /// brings every application back.
  private func scopeBandRow(_ band: ScopeBand) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Label("\(band.appName) only", systemImage: "macwindow")
          .font(.system(size: scaled(12), weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        Spacer(minLength: 0)
        if let key = band.toggleKey {
          Text("\(key)  All apps")
            .font(.system(size: scaled(11), design: .monospaced))
            .foregroundStyle(.tertiary)
        }
      }
      .padding(.horizontal, 12)
      .frame(maxHeight: .infinity)
      Divider()
        .padding(.horizontal, 12)
    }
    .frame(height: PanelMetrics.scopeBandHeight(for: textScale))
  }

  /// The heading over one subgroup: one row's height and no more.
  private func subgroupHeading(_ subgroup: DisplaySubgroup, nested: Bool) -> some View {
    Text(heading(for: subgroup).uppercased())
      .font(.system(size: scaled(11), weight: .semibold))
      .tracking(0.3)
      .foregroundStyle(.tertiary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: PanelMetrics.rowHeight(for: textScale))
      // A List row adds its vertical insets to the frame, so any here
      // would draw the heading taller than the one row the panel height
      // counts for it.
      .listRowInsets(EdgeInsets(top: 0, leading: nested ? 40 : 12, bottom: 0, trailing: 12))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
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
    case .windowlessApp:
      "Apps Without Windows"
    }
  }

  private func row(_ window: WindowItem, isInSubgroup: Bool = false) -> some View {
    WindowRow(
      window: window,
      isSelected: window.id == selectedID,
      rowNumber: number(for: window.id),
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
    // A click always picks the row and commits to it, whatever the
    // switches say. Drags and right clicks never reach here: the
    // gesture only answers a plain left click.
    .onTapGesture {
      onClickRow?(window.id)
    }
    .modifier(HoverSelectionModifier(
      id: window.id,
      enabled: hoverSelect,
      anchor: hoverAnchor,
      onHoverRow: onHoverRow
    ))
  }

}
