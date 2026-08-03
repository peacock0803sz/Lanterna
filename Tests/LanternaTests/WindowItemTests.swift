import AppKit
@testable import Lanterna
import Testing

@MainActor
struct WindowItemTests {
    private func item(appName: String) -> WindowItem {
        WindowItem(
            appName: appName,
            bundleIdentifier: nil,
            windowTitle: "Untitled",
            icon: NSImage()
        )
    }

    @Test func shortcutHintUsesFirstTwoCharactersLowercased() {
        #expect(item(appName: "Safari").shortcutHint == "sa")
        #expect(item(appName: "Google Chrome").shortcutHint == "go")
    }

    @Test func shortcutHintFallsBackToWholeNameWhenShorter() {
        #expect(item(appName: "X").shortcutHint == "x")
        #expect(item(appName: "").shortcutHint == "")
    }

    @Test func shortcutHintHandlesNonASCIINames() {
        #expect(item(appName: "メモ").shortcutHint == "メモ")
    }
}
