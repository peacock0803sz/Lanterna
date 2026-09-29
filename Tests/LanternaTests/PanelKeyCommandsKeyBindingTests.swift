import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// Drives one appearance's key commands with a custom table.
@MainActor
private struct KeyCommandFixture {
    let commands: PanelKeyCommands
    let surface: FakeSurface
    let log: DiagnosticsLog

    init(rows: [WindowItem], keyBindings: KeyBindingTable) {
        surface = FakeSurface()
        surface.isPresented = true
        log = DiagnosticsLog()
        let selection = PanelSelection(surface: surface)
        let wayOut = PanelExit(
            surface: surface,
            now: { ContinuousClock.now },
            writeLine: log.write,
            switcher: FakeWindowSwitcher(),
            recordCommit: { _, _ in },
            noteSwitchReturned: {},
            onPanelGone: {}
        )
        commands = PanelKeyCommands(
            surface: surface,
            selection: selection,
            wayOut: wayOut,
            keyBindings: keyBindings,
            now: { ContinuousClock.now }
        )
        commands.beginFiltering(fullWindows: rows, filtering: true)
        commands.activateFiltering()
    }

    /// Types one character through the commands, as a user would.
    func typeCharacter(_ keyCode: Int, _ character: String) {
        _ = commands.handle(PanelKeystroke(
            keyCode: UInt16(keyCode), modifiers: [], isARepeat: false,
            characters: character
        ))
    }

    /// Presses one non-typing key through the commands.
    func pressKey(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) {
        _ = commands.handle(PanelKeystroke(
            keyCode: UInt16(keyCode), modifiers: modifiers, isARepeat: false,
            characters: ""
        ))
    }
}

@MainActor
private func commandRows() -> [WindowItem] {
    [
        operationRow(appName: "Safari", windowTitle: "Tabs", windowID: 1),
        operationRow(appName: "Finder", windowTitle: "AirDrop", windowID: 2),
    ]
}

@MainActor
struct PanelKeyCommandsKeyBindingTests {
    /// A dedicated clear key clears the query and leaves the panel up.
    @Test func clearKeyClearsQueryAndStaysUp() {
        var table = KeyBindingTable.defaults
        table.keys[.clearQuery] = [ResolvedKey(keyCode: 96, modifiers: [])]
        let fixture = KeyCommandFixture(rows: commandRows(), keyBindings: table)
        fixture.typeCharacter(kVK_ANSI_S, "s")
        fixture.pressKey(96)
        #expect(fixture.surface.updatedQueries.last == "")
        #expect(fixture.surface.isPresented)
    }

    /// Escape still clears first under the default table.
    @Test func escapeClearsFirstUnderDefaults() {
        let fixture = KeyCommandFixture(rows: commandRows(), keyBindings: .defaults)
        fixture.typeCharacter(kVK_ANSI_S, "s")
        fixture.pressKey(kVK_Escape)
        #expect(fixture.surface.updatedQueries.last == "")
        #expect(fixture.surface.isPresented)
    }

    /// A cancel key outside the clear list cancels at once, query or not.
    @Test func cancelOutsideClearListCancelsAtOnce() {
        var table = KeyBindingTable.defaults
        table.keys[.cancel] = [ResolvedKey(keyCode: 97, modifiers: [])]
        let fixture = KeyCommandFixture(rows: commandRows(), keyBindings: table)
        fixture.typeCharacter(kVK_ANSI_S, "s")
        fixture.pressKey(97)
        #expect(!fixture.surface.isPresented)
        #expect(fixture.log.lines.contains { $0.contains("cancelled") })
    }
}
