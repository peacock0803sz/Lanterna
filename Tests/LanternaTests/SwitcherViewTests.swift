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
  /// The rows the list draws are the rows the panel's height counts: one
  /// for each window, and one heading row for each non-empty subgroup. Said of the count alone: measuring row
  /// rects off a window that was never shown reads OS-version layout
  /// output, which is not the same on every macOS. Heights hold by
  /// construction instead — every row carries an explicit frame of one
  /// row's height — and `PanelMetricsTests` holds the counting.
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
      contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.maximumHeight),
      styleMask: [],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let table = tables(in: host).first
    #expect(table?.numberOfRows == PanelMetrics.drawnRowCount(windows))
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
}
