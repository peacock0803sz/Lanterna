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
    /// The rows the list lays out are the rows the panel's height counts,
    /// each as tall as a row: the separator above the parked rows included,
    /// since the list gives it a row's height like any other.
    @Test(arguments: [false, true])
    func theListDrawsTheRowsTheHeightCounts(parked: Bool) {
        let sample = SampleWindows.make(count: 3)
        let windows = parked ? [sample[0], sample[1], sample[2].settingHidden(true)] : sample
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
        let heights = (0 ..< (table?.numberOfRows ?? 0)).map { table?.rect(ofRow: $0).height }
        #expect(heights.allSatisfy { $0 == PanelMetrics.rowHeight })
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
