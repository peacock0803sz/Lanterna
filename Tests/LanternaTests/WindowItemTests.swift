import AppKit
@testable import Lanterna
import Testing

@MainActor
struct WindowItemTests {
    private func item(
        appName: String = "Safari",
        windowTitle: String = "Untitled",
        windowID: CGWindowID = 1,
        isMinimized: Bool = false,
        isHidden: Bool = false
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
            icon: NSImage()
        )
    }

    @Test func shortcutHintUsesFirstTwoCharactersLowercased() {
        #expect(item(appName: "Safari").shortcutHint == "sa")
        #expect(item(appName: "Google Chrome").shortcutHint == "go")
    }

    @Test func shortcutHintFallsBackToWholeNameWhenShorter() {
        #expect(item(appName: "X").shortcutHint == "x")
    }

    @Test func shortcutHintHandlesNonASCIINames() {
        #expect(item(appName: "メモ").shortcutHint == "メモ")
    }

    @Test func windowsWithTheSameIDAreTheSameRow() {
        #expect(item(windowID: 42).id == item(windowID: 42).id)
        #expect(Set([item(windowID: 42).id, item(windowID: 42).id]).count == 1)
    }

    /// Two windows of one application often carry the same title, so identity
    /// must come from the id alone.
    @Test func windowsWithDifferentIDsAreDifferentRows() {
        let first = item(windowTitle: "Downloads", windowID: 42)
        let second = item(windowTitle: "Downloads", windowID: 43)
        #expect(first.id != second.id)
        #expect(Set([first.id, second.id]).count == 2)
    }

    @Test func displayTitleUsesTheWindowTitleWhenItHasContent() {
        #expect(item(windowTitle: "Downloads").displayTitle == "Downloads")
    }

    /// Trimming answers "is this title empty?" and nothing else: what the title
    /// bar shows is what the row shows.
    @Test func displayTitleKeepsSurroundingWhitespaceOfANonEmptyTitle() {
        #expect(item(windowTitle: "  Downloads  ").displayTitle == "  Downloads  ")
    }

    /// A minimized or hidden row parks below the separator; an ordinary
    /// row does not.
    @Test func parkedRowsAreTheMinimizedOrHiddenOnes() {
        #expect(item().isParked == false)
        #expect(item(isMinimized: true).isParked == true)
        #expect(item(isHidden: true).isParked == true)
    }

    @Test func displayTitleFallsBackToTheApplicationNameWhenTheTitleIsEmpty() {
        #expect(item(appName: "Ghostty", windowTitle: "").displayTitle == "Ghostty")
    }

    @Test(arguments: [" ", "   ", "\n", " \t\n "])
    func displayTitleFallsBackToTheApplicationNameWhenTheTitleIsBlank(title: String) {
        #expect(item(appName: "Ghostty", windowTitle: title).displayTitle == "Ghostty")
    }

    @Test(arguments: ["Downloads", "", " ", "\n"])
    func displayTitleIsNeverEmpty(title: String) {
        #expect(!item(appName: "Ghostty", windowTitle: title).displayTitle.isEmpty)
    }

    /// The defaults keep the long-standing arrangement: ordinary rows in
    /// arrival order, then the hidden-app subgroup, then minimized.
    @Test func defaultModesKeepTheLongStandingArrangement() {
        let rows = [
            item(windowTitle: "min-one", windowID: 1, isMinimized: true),
            item(windowTitle: "plain-one", windowID: 2),
            item(windowTitle: "hidden-one", windowID: 3, isHidden: true),
            item(windowTitle: "plain-two", windowID: 4),
            item(windowTitle: "min-two", windowID: 5, isMinimized: true),
            item(windowTitle: "hidden-two", windowID: 6, isHidden: true),
        ]
        let ordered = DisplayModes.displayOrdered(
            rows,
            modes: .defaults,
            queryIsEmpty: true,
            matches: Set(rows.map(\.id))
        )
        #expect(ordered.map(\.id.windowID) == [2, 4, 3, 6, 1, 5])
    }

    /// With a single parked kind the new ordering agrees with `parkedLast`.
    @Test func defaultModesAgreeWithParkedLastForOneParkedKind() {
        let rows = [
            item(windowTitle: "min-one", windowID: 1, isMinimized: true),
            item(windowTitle: "plain-one", windowID: 2),
            item(windowTitle: "min-two", windowID: 3, isMinimized: true),
        ]
        let ordered = DisplayModes.displayOrdered(
            rows,
            modes: .defaults,
            queryIsEmpty: true,
            matches: Set(rows.map(\.id))
        )
        #expect(ordered.map(\.id) == WindowItem.parkedLast(rows).map(\.id))
    }
}
