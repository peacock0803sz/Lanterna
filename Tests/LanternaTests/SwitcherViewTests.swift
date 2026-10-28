import AppKit
@testable import Lanterna
import SwiftUI
import Testing

/// Every table under the view, depth first.
@MainActor
private func tables(in view: NSView) -> [NSTableView] {
  ([view as? NSTableView].compactMap(\.self)) + view.subviews.flatMap { tables(in: $0) }
}

// MARK: - SwitcherViewTests

@MainActor
struct SwitcherViewTests {

  // MARK: Internal

  /// The rows the list draws are the rows the panel's height counts: one
  /// for each window, and one heading row for each non-empty subgroup.
  /// Said of the count alone: an absolute row rect off a window that was
  /// never shown reads OS-version layout output, which is not the same on
  /// every macOS. Heights hold because every row carries a frame of one
  /// row's height and no vertical row inset on top of it; the heading test
  /// below checks that relative to a window row, and `PanelMetricsTests`
  /// holds the counting.
  @Test(arguments: [0, 1, 3])
  func theListDrawsTheRowsTheHeightCounts(parkedCount: Int) {
    let sample = SampleWindows.make(count: 3)
    let windows = sample.enumerated().map { index, row in
      index >= sample.count - parkedCount ? row.settingHidden(true) : row
    }
    let host = NSHostingView(rootView: SwitcherView(
      windows: windows,
      selectedID: nil,
      appearanceToken: 0,
      query: "",
      filterActive: false
    ))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: 400),
      styleMask: [],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let table = tables(in: host).first
    #expect(table?.numberOfRows == PanelMetrics.drawnRowCount(windows))
  }

  /// A subgroup heading is as tall as a window row, since the panel height
  /// counts it as one. Said relative to the window row laid out beside it
  /// rather than as an absolute number, which is OS-version layout output.
  @Test(arguments: TextScaleLevel.allCases)
  func theHeadingIsAsTallAsAWindowRow(level: TextScaleLevel) throws {
    let sample = SampleWindows.make(count: 2)
    let windows = [sample[0], sample[1].settingHidden(true)]
    let host = NSHostingView(rootView: SwitcherView(
      windows: windows,
      selectedID: nil,
      appearanceToken: 0,
      query: "",
      filterActive: false,
      textScale: level
    ))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width(for: level), height: 400),
      styleMask: [],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let table = try #require(tables(in: host).first)
    // The ordinary row, then the heading, then the hidden window under it.
    try #require(table.numberOfRows == 3)
    #expect(table.rect(ofRow: 1).height == table.rect(ofRow: 0).height)
  }

  /// A badge lies over the icon and takes no room, so a row is as tall
  /// with one as without. Said relative to the same row drawn bare.
  @Test(arguments: TextScaleLevel.allCases)
  func aBadgeLeavesTheRowHeightAlone(level: TextScaleLevel) throws {
    let bare = try firstRowHeight(badges: .none, level: level)
    let badged = try firstRowHeight(badges: SampleWindows.sampleBadges, level: level)
    #expect(badged == bare)
  }

  /// A row is handed the badge of its application out of the table the
  /// panel was given, and none when the table holds none for it.
  @Test
  func aRowIsHandedItsApplicationsBadge() {
    let windows = SampleWindows.make(count: 2)
    var view = SwitcherView(windows: windows, selectedID: nil, appearanceToken: 0, query: "", filterActive: false)
    #expect(view.badge(for: windows[0]) == nil)
    view.badges = SampleWindows.sampleBadges
    #expect(windows.map { view.badge(for: $0) } == [.count(3), .count(3)])
  }

  /// The view draws whichever row it is told to, and nothing about the list
  /// decides that any more. Said by handing in a row that is not the first
  /// one: with the old derivation in place this could only ever have read
  /// back the first, so the case is one the view could not have passed
  /// before it was given the choice from outside.
  @Test
  func theChosenRowIsTheOneItWasHanded() {
    let windows = SampleWindows.standard()
    let third = windows[2].id
    #expect(
      SwitcherView(windows: windows, selectedID: third, appearanceToken: 0, query: "", filterActive: false)
        .selectedID == third
    )
  }

  /// Nothing chosen is a state the view has to be able to draw: the panel
  /// goes up over an empty list whenever the window enumeration comes back
  /// with nothing.
  @Test
  func nothingNeedBeChosen() {
    #expect(
      SwitcherView(
        windows: SampleWindows.standard(),
        selectedID: nil,
        appearanceToken: 0,
        query: "",
        filterActive: false
      ).selectedID == nil
    )
    #expect(
      SwitcherView(windows: [], selectedID: nil, appearanceToken: 1, query: "", filterActive: false)
        .selectedID == nil
    )
  }

  /// The query divides around the insertion point: what stands before
  /// it and what stands after it. Out-of-range points clamp to the ends.
  @Test
  func theQuerySplitsAroundTheInsertionPoint() {
    #expect(SwitcherView.splitQuery("safari", at: 0) == ("", "safari"))
    #expect(SwitcherView.splitQuery("safari", at: 2) == ("sa", "fari"))
    #expect(SwitcherView.splitQuery("safari", at: 6) == ("safari", ""))
    #expect(SwitcherView.splitQuery("safari", at: 99) == ("safari", ""))
    #expect(SwitcherView.splitQuery("", at: 0) == ("", ""))
  }

  /// The view carries the insertion point beside the query.
  @Test
  func theViewCarriesTheInsertionPoint() {
    #expect(
      SwitcherView(windows: [], selectedID: nil, appearanceToken: 0, query: "sa", cursor: 1, filterActive: true)
        .cursor == 1
    )
  }

  /// The query row names how many window rows the list draws, singular
  /// for one and plural otherwise, zero included.
  @Test
  func theCountWordingFollowsTheRowCount() {
    let windows = SampleWindows.make(count: 2)
    #expect(SwitcherView.countWording(ordinary: [], subgroups: []) == "0 windows")
    #expect(SwitcherView.countWording(ordinary: [windows[0]], subgroups: []) == "1 window")
    #expect(SwitcherView.countWording(ordinary: windows, subgroups: []) == "2 windows")
  }

  /// Subgrouped rows count like ordinary ones, and the headings over them
  /// do not count at all.
  @Test
  func theCountTakesSubgroupRowsAndNoHeadings() {
    let windows = SampleWindows.make(count: 3)
    let split = DisplayModes.sections(
      of: [windows[0], windows[1].settingMinimized(true), windows[2].settingHidden(true)],
      modes: .defaults,
      query: ""
    )
    #expect(split.subgroups.count == 2)
    #expect(SwitcherView.countWording(ordinary: split.ordinary, subgroups: split.subgroups) == "3 windows")
    let lone = DisplayModes.sections(of: [windows[0].settingHidden(true)], modes: .defaults, query: "")
    #expect(SwitcherView.countWording(ordinary: lone.ordinary, subgroups: lone.subgroups) == "1 window")
  }

  // MARK: Private

  /// The view over sample rows, laid out in a window of the panel's width.
  private func hosted(badges: AppBadges, level: TextScaleLevel) -> NSHostingView<SwitcherView> {
    var view = SwitcherView(
      windows: SampleWindows.make(count: 2),
      selectedID: nil,
      appearanceToken: 0,
      query: "",
      filterActive: false,
      textScale: level
    )
    view.badges = badges
    let host = NSHostingView(rootView: view)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width(for: level), height: 400),
      styleMask: [],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    return host
  }

  private func firstRowHeight(badges: AppBadges, level: TextScaleLevel) throws -> CGFloat {
    let table = try #require(tables(in: hosted(badges: badges, level: level)).first)
    try #require(table.numberOfRows > 0)
    return table.rect(ofRow: 0).height
  }

}
