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
    isMinimized: Bool = false
) -> WindowItem {
    WindowItem(
        id: WindowItem.Identifier(windowID: windowID),
        ownerProcessIdentifier: 0,
        appName: appName,
        bundleIdentifier: nil,
        windowTitle: windowTitle,
        kind: .standard,
        isMinimized: isMinimized,
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

    private func presenter(modes: DisplayModes) -> (PanelPresenter, FakeSurface) {
        let surface = FakeSurface()
        let log = DiagnosticsLog()
        let presenter = PanelPresenter(
            surface: surface,
            store: WindowListStore(fixed: rows),
            displayModes: modes,
            writeLine: log.write,
            switcher: FakeWindowSwitcher()
        )
        return (presenter, surface)
    }

    /// Every combination that opens a panel narrows before the cursor and
    /// the panel are fed: the hidden row is not drawn, not chosen, and no
    /// run of the arrows lands on it.
    @Test(arguments: [HotkeyCombination.forward, .filter])
    func aHiddenRowIsNeverShownChosenOrSteppedOnto(combination: HotkeyCombination) {
        let (presenter, surface) = presenter(modes: minimizedHidden)
        let hidden = rows[1].id
        presenter.handleHotkey(combination, deliveryDelay: nil)
        #expect(surface.presentedLists.first?.map(\.id) == [rows[0].id, rows[2].id, rows[3].id])
        #expect(presenter.selection.chosenID == rows[2].id)
        var visited: [WindowItem.Identifier?] = []
        for _ in 0 ..< rows.count * 2 {
            _ = presenter.handleKeyStroke(press(kVK_DownArrow))
            visited.append(presenter.selection.chosenID)
        }
        #expect(!visited.contains(hidden))
        #expect(!surface.shownSelections.contains(hidden))
    }
}
