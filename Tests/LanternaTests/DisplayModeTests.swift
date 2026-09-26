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
        isHidden: Bool = false,
        isOnOtherSpace: Bool = false,
        isFullscreen: Bool = false
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
            isOnOtherSpace: isOnOtherSpace,
            isFullscreen: isFullscreen,
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

    @Test func hiddenAppKindsObeyTheirMode() {
        let row = item(isHidden: true)
        #expect(placement(of: row, modes: modes(hiddenApp: .show)) == .ordinary)
        #expect(placement(of: row, modes: modes(hiddenApp: .hide)) == .hidden)
        #expect(
            placement(
                of: row,
                modes: modes(hiddenApp: .hide),
                queryIsEmpty: false,
                matchesQuery: true
            ) == .separated(.hiddenApp)
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

    /// A kind shown in the list files nothing under its heading: the row
    /// parks under the kind whose mode parks it.
    @Test func aShownKindYieldsTheSubgroupToTheParkingKind() {
        let row = item(isMinimized: true, isHidden: true)
        #expect(
            placement(of: row, modes: modes(hiddenApp: .show)) == .separated(.minimized)
        )
    }

    /// A row escaping hiding on a match goes under the kind that hid it,
    /// not under an earlier kind that only parks it.
    @Test func anEscapedRowGoesUnderTheHidingKind() {
        let row = item(isMinimized: true, isHidden: true)
        #expect(
            placement(
                of: row,
                modes: modes(minimized: .hide),
                queryIsEmpty: false,
                matchesQuery: true
            ) == .separated(.minimized)
        )
    }

    @Test func otherSpaceKindsObeyTheirMode() {
        // A row not known to be on another Space stays ordinary no matter
        // the mode; unknown never hides.
        #expect(placement(of: item(), modes: modes(otherSpace: .hide)) == .ordinary)
        let row = item(isOnOtherSpace: true)
        #expect(placement(of: row, modes: modes(otherSpace: .show)) == .ordinary)
        #expect(placement(of: row, modes: modes(otherSpace: .hide)) == .hidden)
        #expect(
            placement(of: row, modes: modes(otherSpace: .separateAtBottom))
                == .separated(.otherSpace)
        )
    }

    @Test func fullscreenKindsObeyTheirMode() {
        let row = item(isFullscreen: true)
        #expect(placement(of: row, modes: modes(fullscreen: .show)) == .ordinary)
        #expect(placement(of: row, modes: modes(fullscreen: .hide)) == .hidden)
        #expect(placement(of: row, modes: modes()) == .ordinary)
        #expect(
            placement(of: row, modes: modes(fullscreen: .separateAtBottom))
                == .separated(.fullscreen)
        )
    }

    @Test func orderingKeepsOrdinaryFirstAndSubgroupsInOrder() {
        let rows = [
            item(windowID: 1, isMinimized: true),
            item(windowID: 2),
            item(windowID: 3, isHidden: true),
            item(windowID: 4),
        ]
        let ordered = DisplayModes.displayOrdered(rows, modes: modes(), query: "")
        #expect(ordered.map(\.id.windowID) == [2, 4, 3, 1])
    }
}
