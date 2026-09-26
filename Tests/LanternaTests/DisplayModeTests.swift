import AppKit
@testable import Lanterna
import Testing

struct DisplayModeTests {
    private func modes(
        otherSpace: DisplayMode = .show,
        hiddenApp: DisplayMode = .separateAtBottom,
        minimized: DisplayMode = .separateAtBottom,
        fullscreen: DisplayMode = .show
    ) -> DisplayModes {
        DisplayModes(
            otherSpace: otherSpace,
            hiddenApp: hiddenApp,
            minimized: minimized,
            fullscreen: fullscreen
        )
    }

    private func item(
        windowID: CGWindowID = 1,
        isMinimized: Bool = false,
        isHidden: Bool = false
    ) -> WindowItem {
        WindowItem(
            id: WindowItem.Identifier(windowID: windowID),
            ownerProcessIdentifier: 0,
            appName: "Safari",
            bundleIdentifier: nil,
            windowTitle: "Untitled",
            kind: .standard,
            isMinimized: isMinimized,
            isHidden: isHidden,
            icon: NSImage()
        )
    }

    private func placement(
        of row: WindowItem,
        modes: DisplayModes,
        queryIsEmpty: Bool = true,
        matchesQuery: Bool = false
    ) -> RowPlacement {
        DisplayModes.placement(
            of: row,
            modes: modes,
            queryIsEmpty: queryIsEmpty,
            matchesQuery: matchesQuery
        )
    }

    @Test func defaultsMatchTheLongStandingArrangement() {
        #expect(DisplayModes.defaults == modes())
    }

    @Test func plainRowsStayOrdinary() {
        #expect(placement(of: item(), modes: modes()) == .ordinary)
    }

    @Test func shownKindsStayOrdinary() {
        let row = item(isMinimized: true)
        #expect(placement(of: row, modes: modes(minimized: .show)) == .ordinary)
    }

    @Test func hiddenRowsVanishWithoutAQuery() {
        let row = item(isMinimized: true)
        #expect(placement(of: row, modes: modes(minimized: .hide)) == .hidden)
    }

    @Test func hiddenRowsReturnToTheirSubgroupOnAMatch() {
        let row = item(isMinimized: true)
        #expect(
            placement(
                of: row,
                modes: modes(minimized: .hide),
                queryIsEmpty: false,
                matchesQuery: true
            ) == .separated(.minimized)
        )
    }

    @Test func separatedRowsParkBelow() {
        #expect(
            placement(of: item(isMinimized: true), modes: modes())
                == .separated(.minimized)
        )
        #expect(
            placement(of: item(isHidden: true), modes: modes())
                == .separated(.hiddenApp)
        )
    }

    @Test func hidingWinsOverSeparating() {
        let row = item(isMinimized: true, isHidden: true)
        #expect(
            placement(of: row, modes: modes(hiddenApp: .hide)) == .hidden
        )
    }

    @Test func firstSubgroupInFixedOrderWinsTies() {
        // Both kinds separate: hidden-app comes before minimized.
        let row = item(isMinimized: true, isHidden: true)
        #expect(
            placement(of: row, modes: modes()) == .separated(.hiddenApp)
        )
    }

    @Test func orderingKeepsOrdinaryFirstAndSubgroupsInOrder() {
        let rows = [
            item(windowID: 1, isMinimized: true),
            item(windowID: 2),
            item(windowID: 3, isHidden: true),
            item(windowID: 4),
        ]
        let ordered = DisplayModes.displayOrdered(
            rows,
            modes: modes(),
            queryIsEmpty: true,
            matches: Set(rows.map(\.id))
        )
        #expect(ordered.map(\.id.windowID) == [2, 4, 3, 1])
    }
}
