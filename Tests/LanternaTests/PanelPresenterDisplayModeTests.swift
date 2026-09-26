import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// Rows with distinct names, so which rows a query matches is decided here.
@MainActor
private func modeRow(
    appName: String,
    windowTitle: String,
    windowID: CGWindowID,
    isMinimized: Bool = false,
    isHidden: Bool = false,
    isFullscreen: Bool = false
) -> WindowItem {
    WindowItem(
        id: WindowItem.Identifier(windowID: windowID),
        ownerProcessIdentifier: 0,
        appName: appName,
        bundleIdentifier: nil,
        windowTitle: windowTitle,
        kind: .standard,
        isMinimized: isMinimized,
        isHidden: isHidden,
        isFullscreen: isFullscreen,
        icon: NSImage(size: NSSize(width: 1, height: 1))
    )
}

private func press(_ keyCode: Int, characters: String = "") -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(keyCode), modifiers: [], isARepeat: false, characters: characters)
}

/// The display modes seen from the presenter: what reaches the panel, the
/// choice, and the arrows, from the first frame of an appearance on.
@MainActor
struct PanelPresenterDisplayModeTests {
    private let minimizedHidden = DisplayModes(
        otherSpace: .show,
        hiddenApp: .separateAtBottom,
        minimized: .hide,
        fullscreen: .show
    )

    /// The second row is the minimized one, so a cursor fed the whole list
    /// would open on it.
    private var rows: [WindowItem] {
        [
            modeRow(appName: "Safari", windowTitle: "Front page", windowID: 1),
            modeRow(appName: "Preview", windowTitle: "Buried notes", windowID: 2, isMinimized: true),
            modeRow(appName: "Finder", windowTitle: "Applications", windowID: 3),
            modeRow(appName: "Mail", windowTitle: "Inbox", windowID: 4),
        ]
    }

    private func presenter(
        modes: DisplayModes,
        rows: [WindowItem]? = nil
    ) -> (PanelPresenter, FakeSurface) {
        let surface = FakeSurface()
        let log = DiagnosticsLog()
        let presenter = PanelPresenter(
            surface: surface,
            store: WindowListStore(fixed: rows ?? self.rows),
            displayModes: modes,
            writeLine: log.write,
            switcher: FakeWindowSwitcher()
        )
        return (presenter, surface)
    }

    /// Every combination that opens a panel narrows before the cursor and
    /// the panel are fed: the hidden row is not drawn, not chosen, and no
    /// run of the arrows lands on it.
    @Test(arguments: [HotkeyCombination.forward, .reverse, .filter])
    func aHiddenRowIsNeverShownChosenOrSteppedOnto(combination: HotkeyCombination) {
        let (presenter, surface) = presenter(modes: minimizedHidden)
        let hidden = rows[1].id
        presenter.handleHotkey(combination, deliveryDelay: nil)
        #expect(surface.presentedLists.first?.map(\.id) == [rows[0].id, rows[2].id, rows[3].id])
        #expect(surface.presentedActives == [combination == .filter])
        #expect(presenter.selection.chosenID == rows[2].id)
        var visited: [WindowItem.Identifier?] = []
        for _ in 0 ..< rows.count * 2 {
            _ = presenter.handleKeyStroke(press(kVK_DownArrow))
            visited.append(presenter.selection.chosenID)
        }
        #expect(!visited.contains(hidden))
        #expect(!surface.shownSelections.contains(hidden))
    }

    /// The modes the presenter was built with reach the filter: the hidden
    /// row stays out while the query is empty, and comes back once typing
    /// matches it.
    @Test func thePresentersModesReachTheFilter() {
        let (presenter, surface) = presenter(modes: minimizedHidden)
        presenter.handleHotkey(.filter, deliveryDelay: nil)
        #expect(presenter.keyCommands.shownWindows.map(\.id) == [rows[0].id, rows[2].id, rows[3].id])
        for character in "buried" {
            _ = presenter.handleKeyStroke(press(kVK_ANSI_A, characters: String(character)))
        }
        #expect(surface.updatedLists.last?.map(\.id) == [rows[1].id])
        #expect(presenter.selection.chosenID == rows[1].id)
    }

    /// Opens a panel over rows arriving in the given order, and holds the
    /// arrows to the order the view draws them in: the panel is handed the
    /// rows as the view splits them, and one lap of the arrows from the
    /// opening choice visits them in that order.
    private func expectStepsAsDrawn(
        modes: DisplayModes,
        arriving: [WindowItem],
        drawn expected: [WindowItem],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let (presenter, surface) = presenter(modes: modes, rows: arriving)
        presenter.handleHotkey(.forward, deliveryDelay: nil)
        let presented = surface.presentedLists.first ?? []
        let (ordinary, subgroups) = DisplayModes.sections(of: presented, modes: modes, query: "")
        let drawn = (ordinary + subgroups.flatMap(\.1)).map(\.id)
        #expect(drawn == expected.map(\.id), sourceLocation: sourceLocation)
        #expect(presented.map(\.id) == drawn, sourceLocation: sourceLocation)
        var lap = [presenter.selection.chosenID]
        for _ in 1 ..< drawn.count {
            _ = presenter.handleKeyStroke(press(kVK_DownArrow))
            lap.append(presenter.selection.chosenID)
        }
        #expect(lap == Array(drawn[1...] + drawn[..<1]), sourceLocation: sourceLocation)
    }

    /// Hidden-app and minimized rows interleaved in recent use step through
    /// their subgroups the way they are drawn, not in recent-use order.
    @Test func interleavedParkedRowsStepAsDrawn() {
        let front = modeRow(appName: "Safari", windowTitle: "Front page", windowID: 1)
        let firstMinimized = modeRow(appName: "Preview", windowTitle: "Notes", windowID: 2, isMinimized: true)
        let hidden = modeRow(appName: "Mail", windowTitle: "Inbox", windowID: 3, isHidden: true)
        let secondMinimized = modeRow(appName: "Notes", windowTitle: "Draft", windowID: 4, isMinimized: true)
        expectStepsAsDrawn(
            modes: .defaults,
            arriving: [front, firstMinimized, hidden, secondMinimized],
            drawn: [front, hidden, firstMinimized, secondMinimized]
        )
    }

    /// A kind shown in the list keeps its recent-use place among the
    /// ordinary rows.
    @Test func aShownKindKeepsItsRecentUsePlace() {
        let front = modeRow(appName: "Safari", windowTitle: "Front page", windowID: 1)
        let hidden = modeRow(appName: "Mail", windowTitle: "Inbox", windowID: 2, isHidden: true)
        let back = modeRow(appName: "Finder", windowTitle: "Applications", windowID: 3)
        let minimized = modeRow(appName: "Preview", windowTitle: "Notes", windowID: 4, isMinimized: true)
        expectStepsAsDrawn(
            modes: DisplayModes(otherSpace: .show, hiddenApp: .show, minimized: .separateAtBottom, fullscreen: .show),
            arriving: [front, hidden, back, minimized],
            drawn: [front, hidden, back, minimized]
        )
    }

    /// Fullscreen rows parked below step last, after the minimized ones,
    /// the way their subgroup draws last.
    @Test func separatedFullscreenRowsStepAsDrawn() {
        let front = modeRow(appName: "Safari", windowTitle: "Front page", windowID: 1)
        let fullscreen = modeRow(appName: "Keynote", windowTitle: "Talk", windowID: 2, isFullscreen: true)
        let minimized = modeRow(appName: "Preview", windowTitle: "Notes", windowID: 3, isMinimized: true)
        let back = modeRow(appName: "Finder", windowTitle: "Applications", windowID: 4)
        expectStepsAsDrawn(
            modes: DisplayModes(
                otherSpace: .show,
                hiddenApp: .separateAtBottom,
                minimized: .separateAtBottom,
                fullscreen: .separateAtBottom
            ),
            arriving: [front, fullscreen, minimized, back],
            drawn: [front, back, minimized, fullscreen]
        )
    }
}
