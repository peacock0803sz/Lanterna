import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

private func filteringStroke(
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

// MARK: - PanelStartFilteringTests

/// Switching an open panel into filtering with the S key.
@MainActor
struct PanelStartFilteringTests {
  @Test
  func commandHeldSSwitchesLikeTheInvocation() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    let shown = fixture.surface.presentedLists.last?.map(\.id)
    let chosen = fixture.surface.presentedSelections.last
    #expect(fixture.presenter.commandWatch.isLooking)
    #expect(
      fixture.presenter.handleKeyStroke(filteringStroke(kVK_ANSI_S, .command, characters: "s"))
        == .absorbed
    )
    #expect(fixture.surface.presentedLists.count == 1)
    #expect(fixture.surface.presentedSelections.last == chosen)
    #expect(shown?.count == 12)
    #expect(fixture.surface.updatedQueries.last == "")
    #expect(fixture.presenter.keyCommands.isFilteringActive)
    #expect(!fixture.presenter.commandWatch.isLooking)
    _ = fixture.presenter.handleKeyStroke(filteringStroke(kVK_ANSI_J, characters: "j"))
    #expect((fixture.surface.updatedLists.last?.count ?? 12) < 12)
  }

  @Test
  func releaseAfterSwitchingCommitsNothing() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(filteringStroke(kVK_ANSI_S, .command, characters: "s"))
    fixture.presenter.modifierFlagsChanged([])
    fixture.presenter.handleCommandRelease()
    fixture.presenter.handleOptionRelease()
    #expect(fixture.surface.isPresented)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  @Test
  func heldSAfterSwitchingTypesNothingUntilRepressed() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(filteringStroke(kVK_ANSI_S, .command, characters: "s"))
    for _ in 0 ..< 3 {
      _ = fixture.presenter.handleKeyStroke(filteringStroke(
        kVK_ANSI_S,
        .command,
        repeating: true,
        characters: "s"
      ))
    }
    #expect(!fixture.surface.updatedQueries.contains(where: { !$0.isEmpty }))
    _ = fixture.presenter.handleKeyStroke(filteringStroke(kVK_ANSI_S, characters: "s"))
    #expect(fixture.surface.updatedQueries.last == "s")
  }

  @Test
  func sWhileFilteringTypes() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(filteringStroke(kVK_ANSI_S, characters: "s"))
    #expect(fixture.surface.updatedQueries.last == "s")
  }

  /// A start key moved onto a letter held with a modifier still types that
  /// letter while filtering, rather than being swallowed with no effect.
  @Test(arguments: [NSEvent.ModifierFlags.command, .shift])
  func modifiedStartKeyTypesWhileFiltering(modifiers: NSEvent.ModifierFlags) {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    var table = KeyBindingTable.defaults
    table.keys[.startFiltering] = [ResolvedKey(keyCode: UInt16(kVK_ANSI_F), modifiers: modifiers)]
    fixture.presenter.keyBindings = table
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(filteringStroke(kVK_ANSI_F, modifiers, characters: "f"))
    #expect(fixture.surface.updatedQueries.last == "f")
  }

  @Test
  func sSwitchesWhenTheInvocationKeyMoves() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    var table = KeyBindingTable.defaults
    table.keys[.showFilter] = [ResolvedKey(
      keyCode: UInt16(kVK_Space),
      modifiers: [.control, .option]
    )]
    fixture.presenter.keyBindings = table
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(filteringStroke(kVK_ANSI_S, .command, characters: "s"))
    #expect(fixture.presenter.keyCommands.isFilteringActive)
  }

  @Test
  func furtherPressAfterSwitchingClosesWithoutCommitting() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(filteringStroke(kVK_ANSI_S, .command, characters: "s"))
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(!fixture.surface.isPresented)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  @Test
  func furtherPressAfterInvocationSwitchClosesTheSameWay() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(!fixture.surface.isPresented)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }
}
