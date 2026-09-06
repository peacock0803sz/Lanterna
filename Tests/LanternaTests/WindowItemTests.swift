import AppKit
@testable import Lanterna
import Testing

@MainActor
struct WindowItemTests {
    private func item(
        appName: String = "Safari",
        windowTitle: String = "Untitled",
        windowID: CGWindowID = 1
    ) -> WindowItem {
        WindowItem(
            id: WindowItem.Identifier(windowID: windowID),
            ownerProcessIdentifier: 0,
            appName: appName,
            bundleIdentifier: nil,
            windowTitle: windowTitle,
            kind: .standard,
            isMinimized: false,
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
}
