import AppKit
@testable import Lanterna
import SwiftUI
import Testing

/// Every table under the view, depth first.
@MainActor
private func tables(in view: NSView) -> [NSTableView] {
    ([view as? NSTableView].compactMap(\.self)) + view.subviews.flatMap { tables(in: $0) }
}

@MainActor
struct SwitcherViewTests {
    /// The rows the list draws are the rows the panel's height counts: one
    /// for each window, and one more for the separator above the parked
    /// rows when any are parked. Said of the count alone: measuring row
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
            windows: windows, selectedID: nil, appearanceToken: 0, query: "", filterActive: false
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
    @Test func theChosenRowIsTheOneItWasHanded() {
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
    @Test func nothingNeedBeChosen() {
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
}
