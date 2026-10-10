import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

private func settingsStroke(
  _ keyCode: Int,
  _ modifiers: NSEvent.ModifierFlags = [],
  repeating: Bool = false,
  characters: String = ""
) -> PanelKeystroke {
  PanelKeystroke(
    keyCode: UInt16(keyCode),
    modifiers: modifiers,
    isARepeat: repeating,
    characters: characters
  )
}

// MARK: - PanelOpenSettingsTests

/// Opening the settings from the panel, seen from outside the presenter.
@MainActor
struct PanelOpenSettingsTests {
  @Test
  func commandCommaHidesAndOpensSettingsWithoutCommitting() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    var opened = 0
    fixture.presenter.onOpenSettings = { opened += 1 }
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(
      fixture.presenter.handleKeyStroke(settingsStroke(kVK_ANSI_Comma, .command, characters: ","))
        == .absorbed
    )
    #expect(!fixture.surface.isPresented)
    #expect(opened == 1)
    #expect(fixture.log.lines.count(where: { $0.hasPrefix("left for settings ") }) == 1)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("cancelled ") }))
    let afterLeaving = fixture.log.lines
    fixture.presenter.handleCommandRelease()
    #expect(fixture.log.lines == afterLeaving)
  }

  @Test
  func leavingWhileFilteringCarriesTheQuery() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    var opened = 0
    fixture.presenter.onOpenSettings = { opened += 1 }
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    for (code, character) in [(kVK_ANSI_S, "s"), (kVK_ANSI_A, "a"), (kVK_ANSI_F, "f")] {
      _ = fixture.presenter.handleKeyStroke(settingsStroke(code, characters: character))
    }
    _ = fixture.presenter.handleKeyStroke(settingsStroke(kVK_ANSI_Comma, .command, characters: ","))
    #expect(opened == 1)
    #expect(fixture.log.lines.last?.contains("; filter \"saf\" (") == true)
  }

  /// The line names the key the press came in on: each default comma by its
  /// own modifier, and a customized key by position.
  @Test(arguments: [
    (kVK_ANSI_Comma, NSEvent.ModifierFlags.command, false, " after Cmd+Comma"),
    (kVK_ANSI_Comma, .option, false, " after Opt+Comma"),
    (kVK_ANSI_Semicolon, .command, true, " after key 41"),
  ])
  func leavingNamesTheKeyPressed(
    keyCode: Int,
    modifiers: NSEvent.ModifierFlags,
    customized: Bool,
    ending: String
  ) {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    if customized {
      var table = KeyBindingTable.defaults
      table.keys[.openSettings] = [ResolvedKey(keyCode: UInt16(keyCode), modifiers: modifiers)]
      fixture.presenter.keyBindings = table
    }
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(settingsStroke(keyCode, modifiers))
    let line = fixture.log.lines.last { $0.hasPrefix("left for settings ") }
    #expect(line?.hasSuffix(ending) == true)
  }

  @Test
  func repeatedCommaAloneOpensNothing() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    var opened = 0
    fixture.presenter.onOpenSettings = { opened += 1 }
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(
      fixture.presenter.handleKeyStroke(settingsStroke(
        kVK_ANSI_Comma,
        .command,
        repeating: true,
        characters: ","
      )) == .absorbed
    )
    #expect(fixture.surface.isPresented)
    #expect(opened == 0)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("left for settings ") }))
  }
}
