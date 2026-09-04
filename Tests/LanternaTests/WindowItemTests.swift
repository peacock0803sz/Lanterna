import AppKit
@testable import Lanterna
import Testing

@MainActor
struct WindowItemTests {
    private func item(appName: String, id: WindowItem.Identifier = WindowItem.Identifier()) -> WindowItem {
        WindowItem(
            id: id,
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

    @Test func identityIsSuppliedByTheCaller() {
        let id = WindowItem.Identifier()
        #expect(item(appName: "Safari", id: id).id == id)
    }

    @Test func identityHasValueSemantics() {
        let id = WindowItem.Identifier()
        let copy = id
        #expect(copy == id)
        #expect(Set([id, copy]).count == 1)
    }

    @Test func freshIdentitiesAreDistinct() {
        #expect(item(appName: "Safari").id != item(appName: "Safari").id)
        #expect(Set([WindowItem.Identifier(), WindowItem.Identifier()]).count == 2)
    }
}
