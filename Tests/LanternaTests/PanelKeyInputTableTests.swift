import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// Spelled as a press is made: a key, and whatever was held with it.
private func tablePress(
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

/// One table holding a single custom binding for the named action.
private func tableWith(_ action: KeyBindingAction, _ key: ResolvedKey) -> KeyBindingTable {
  var table = KeyBindingTable.defaults
  table.keys[action] = [key]
  return table
}

private func resolved(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> ResolvedKey {
  ResolvedKey(keyCode: UInt16(keyCode), modifiers: modifiers)
}

// MARK: - PanelKeyInputTableTests

struct PanelKeyInputTableTests {
  @Test(arguments: [NSEvent.ModifierFlags(), .command])
  func defaultsTableMovesWithArrows(modifiers: NSEvent.ModifierFlags) {
    let table = KeyBindingTable.defaults
    #expect(PanelKeyInput.action(for: tablePress(kVK_DownArrow, modifiers), table: table) == .selectNext)
    #expect(
      PanelKeyInput.action(for: tablePress(kVK_UpArrow, modifiers), table: table) == .selectPrevious
    )
  }

  @Test
  func defaultsTableAbsorbsTab() {
    #expect(PanelKeyInput.action(for: tablePress(kVK_Tab), table: .defaults) == .absorb)
  }

  @Test
  func defaultsTableKeepsTypingForBareLetters() {
    #expect(
      PanelKeyInput.action(for: tablePress(kVK_ANSI_W, [], characters: "w"), table: .defaults)
        == .filterText("w")
    )
    #expect(
      PanelKeyInput.action(for: tablePress(kVK_ANSI_A, .command, characters: "a"), table: .defaults)
        == .filterText("a")
    )
  }

  @Test
  func customNextRequiresItsModifiers() {
    let table = tableWith(.next, resolved(kVK_DownArrow, .command))
    #expect(PanelKeyInput.action(for: tablePress(kVK_DownArrow), table: table) == .absorb)
    #expect(PanelKeyInput.action(for: tablePress(kVK_DownArrow, .command), table: table) == .selectNext)
  }

  @Test
  func bareLetterBindingYieldsToTyping() {
    let table = tableWith(.next, resolved(kVK_ANSI_N))
    #expect(
      PanelKeyInput.action(for: tablePress(kVK_ANSI_N, [], characters: "n"), table: table)
        == .filterText("n")
    )
  }

  @Test
  func bareFunctionKeyBindingFires() {
    let table = tableWith(.commit, resolved(96))
    #expect(PanelKeyInput.action(for: tablePress(96), table: table) == .commit(.custom(96)))
  }

  @Test
  func assignedTabResolves() {
    let table = tableWith(.next, resolved(kVK_Tab))
    #expect(PanelKeyInput.action(for: tablePress(kVK_Tab), table: table) == .selectNext)
  }

  @Test
  func customCommitDoesNotRepeat() {
    let table = tableWith(.commit, resolved(96))
    #expect(PanelKeyInput.action(for: tablePress(96, repeating: true), table: table) == .absorb)
  }

  @Test
  func customNextRepeats() {
    let table = tableWith(.next, resolved(kVK_DownArrow, .command))
    #expect(
      PanelKeyInput.action(for: tablePress(kVK_DownArrow, .command, repeating: true), table: table)
        == .selectNext
    )
  }

  @Test
  func customOperationResolves() {
    let table = tableWith(.closeWindow, resolved(kVK_ANSI_H, .control))
    #expect(
      PanelKeyInput.action(for: tablePress(kVK_ANSI_H, .control), table: table)
        == .windowOperation(.closeWindow)
    )
    #expect(
      PanelKeyInput.action(for: tablePress(kVK_ANSI_H), table: table) == .absorb
    )
  }

  @Test
  func narrowerCustomCommitBeatsBareNextDefault() {
    let table = tableWith(.commit, resolved(kVK_DownArrow, .shift))
    #expect(
      PanelKeyInput.action(for: tablePress(kVK_DownArrow, .shift), table: table)
        == .commit(.custom(UInt16(kVK_DownArrow)))
    )
    #expect(PanelKeyInput.action(for: tablePress(kVK_DownArrow), table: table) == .selectNext)
  }

  @Test
  func narrowerCustomOperationBeatsWiderDefault() {
    var table = KeyBindingTable.defaults
    table.keys[.quitApplication] = [resolved(kVK_ANSI_W, [.shift, .command])]
    #expect(
      PanelKeyInput.action(for: tablePress(kVK_ANSI_W, [.shift, .command]), table: table)
        == .windowOperation(.quitApplication)
    )
  }

  @Test
  func tieKeepsNextBeforePrevious() {
    var table = KeyBindingTable.defaults
    table.keys[.next] = [resolved(96)]
    table.keys[.previous] = [resolved(96)]
    #expect(PanelKeyInput.action(for: tablePress(96), table: table) == .selectNext)
  }

  @Test
  func tabLostFromInvocationStaysAbsorbed() {
    // No invocation action holds Tab anymore: show moved to Cmd+S,
    // crowding showFilter out, and showReverse moved to Cmd+R. The
    // reservation stands back up, even though next still binds Tab.
    let section: [KeyBindingAction: [RawKeyBinding]] = [
      .show: [RawKeyBinding(keyCode: kVK_ANSI_S, modifiers: ["cmd"])],
      .showReverse: [RawKeyBinding(keyCode: kVK_ANSI_R, modifiers: ["cmd"])],
      .showFilter: [RawKeyBinding(keyCode: kVK_ANSI_S, modifiers: ["cmd"])],
      .next: [RawKeyBinding(keyCode: kVK_Tab, modifiers: [])],
    ]
    let (table, _) = KeyBindingResolver.resolve(
      section,
      order: [.show, .showReverse, .showFilter, .next]
    )
    #expect(PanelKeyInput.action(for: tablePress(kVK_Tab), table: table) == .absorb)
  }

  @Test
  func clearQueryMatchFollowsTheTable() {
    let table = KeyBindingTable.defaults
    #expect(table.matches(tablePress(kVK_Escape), action: .clearQuery))
    #expect(!table.matches(tablePress(kVK_ANSI_Period, .command), action: .clearQuery))
  }
}
