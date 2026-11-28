import AppKit
import Carbon.HIToolbox
import Testing
@testable import Lanterna

private func tabPress(_ modifiers: NSEvent.ModifierFlags) -> PanelKeystroke {
  PanelKeystroke(keyCode: UInt16(kVK_Tab), modifiers: modifiers, isARepeat: false)
}

// MARK: - ParallelPanelKeyInputTests

/// A switched-off parallel switcher never reaches Carbon, so its keys
/// arrive as panel keystrokes instead. With the default table they mean
/// nothing and are absorbed either way: the choice does not move, the
/// panel does not hide, and no query text is typed.
struct ParallelPanelKeyInputTests {

  @Test(arguments: [true, false])
  func defaultTableAbsorbsParallelPresses(filtering: Bool) {
    let table = KeyBindingTable.defaults
    #expect(PanelKeyInput.action(for: tabPress(.option), table: table, filtering: filtering) == .absorb)
    #expect(
      PanelKeyInput.action(for: tabPress([.option, .shift]), table: table, filtering: filtering)
        == .absorb
    )
  }

  @Test(arguments: [true, false])
  func tabBoundNextAnswersParallelPresses(filtering: Bool) {
    // show keeps Cmd+Tab, so the reservation stands whatever the
    // switcher switch says; next takes the bare Tab beside it.
    var table = KeyBindingTable.defaults
    table.keys[.next] = [ResolvedKey(keyCode: UInt16(kVK_Tab), modifiers: [])]
    #expect(
      PanelKeyInput.action(for: tabPress(.option), table: table, filtering: filtering) == .selectNext
    )
  }

  @Test(arguments: [true, false])
  func reservationFollowsEveryInvocation(filtering: Bool) {
    // None of the main three holds Tab anymore, but the parallel pair
    // still does: the reservation stands, so a Tab-bound next answers.
    var table = KeyBindingTable.defaults
    table.keys[.show] = [ResolvedKey(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)]
    table.keys[.showReverse] = [ResolvedKey(keyCode: UInt16(kVK_ANSI_R), modifiers: .command)]
    table.keys[.showFilter] = [ResolvedKey(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)]
    table.keys[.next] = [ResolvedKey(keyCode: UInt16(kVK_Tab), modifiers: [])]
    #expect(
      PanelKeyInput.action(for: tabPress(.option), table: table, filtering: filtering) == .selectNext
    )
  }

}
