import AppKit
@testable import Lanterna
import Testing

/// Rows with distinct names, so which rows match is decided by the test.
@MainActor
private func orderRow(windowID: CGWindowID, title: String, isMinimized: Bool = false) -> WindowItem {
    WindowItem(
        id: WindowItem.Identifier(windowID: windowID),
        ownerProcessIdentifier: 0,
        appName: "App\(windowID)",
        bundleIdentifier: nil,
        windowTitle: title,
        kind: .standard,
        isMinimized: isMinimized,
        icon: NSImage(size: NSSize(width: 1, height: 1))
    )
}

/// The filter's order seen from outside: the rows it hands the panel and
/// the places it counts in are the rows as they are drawn.
@MainActor
struct PanelFilterDisplayOrderTests {
    /// An operation's anchor is counted among the rows as they are drawn.
    /// The parked row arrives first but draws last, so counting the list
    /// as it arrived would hand the choice to the row just minimized.
    @Test func anAnchorCountsAmongTheRowsAsDrawn() {
        let surface = FakeSurface()
        surface.isPresented = true
        let selection = PanelSelection(surface: surface)
        let filter = PanelFilter(selection: selection, surface: surface)
        let parked = orderRow(windowID: 9, title: "Buried notes", isMinimized: true)
        let rows = [
            orderRow(windowID: 1, title: "Front page"),
            orderRow(windowID: 2, title: "Downloads"),
            orderRow(windowID: 3, title: "Applications"),
        ]
        let before = [parked] + rows
        filter.begin(fullWindows: before)
        selection.beginSecond(filter.shownWindows.map(\.id))
        #expect(selection.chosenID == rows[1].id)
        let after = [parked, rows[0], rows[1].settingMinimized(true), rows[2]]
        filter.replace(fullWindows: after, choosingWhere: ChoiceAnchor(id: rows[1].id, stoodIn: before))
        #expect(surface.updatedLists.last?.map(\.id) == [rows[0].id, rows[2].id, parked.id, rows[1].id])
        #expect(selection.chosenID == rows[2].id)
    }
}
