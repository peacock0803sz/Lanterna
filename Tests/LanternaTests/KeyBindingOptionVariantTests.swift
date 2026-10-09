import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// A press the way the hardware spells one: the Option layer never
/// reaches the characters, so an Option letter carries its plain letter.
private func optionPress(
  _ keyCode: Int,
  _ modifiers: NSEvent.ModifierFlags,
  repeating: Bool = false,
  characters: String
) -> PanelKeystroke {
  PanelKeystroke(
    keyCode: UInt16(keyCode),
    modifiers: modifiers,
    isARepeat: repeating,
    characters: characters
  )
}

// MARK: - KeyBindingOptionVariantTests

/// Names the pair a newly added default key overlaps.
///
/// The resolver already fails an overlapping default as a conflict, without
/// naming which two actions share the key. This test points at the pair and
/// the key, so adding a default key shows the existing default it collides with.
@MainActor
struct KeyBindingOptionVariantTests {

  @Test
  func defaultsShareNoKeyAcrossActions() {
    let table = KeyBindingTable.defaults
    let actions = KeyBindingAction.allCases
    for firstIndex in actions.indices {
      for secondIndex in actions.indices where secondIndex > firstIndex {
        let first = actions[firstIndex]
        let second = actions[secondIndex]
        guard !KeyBindingResolver.isExcusedPair(first, second) else { continue }
        let shared = Set(table[first]).intersection(table[second])
        for key in shared {
          Issue.record("\(first.rawValue) and \(second.rawValue) share \(key.displayName)")
        }
      }
    }
  }

  /// Option window keys drive their operations whether filtering or
  /// not. Never reading as filter text pins that the letter never
  /// reaches the query, even mid-filtering.
  @Test(arguments: [
    (kVK_ANSI_W, WindowOperation.closeWindow, "w"),
    (kVK_ANSI_Q, WindowOperation.quitApplication, "q"),
    (kVK_ANSI_H, WindowOperation.hideApplication, "h"),
    (kVK_ANSI_M, WindowOperation.minimizeWindow, "m"),
  ])
  func optionWindowKeysDriveOperations(keyCode: Int, operation: WindowOperation, characters: String) {
    let table = KeyBindingTable.defaults
    for filtering in [false, true] {
      #expect(
        PanelKeyInput.action(
          for: optionPress(keyCode, .option, characters: characters),
          table: table,
          numberJumpEnabled: false,
          reorderEnabled: false,
          filtering: filtering
        ) == .windowOperation(operation)
      )
    }
  }

  @Test
  func combinedModifiersDriveCloseWindow() {
    let table = KeyBindingTable.defaults
    #expect(
      PanelKeyInput.action(
        for: optionPress(kVK_ANSI_W, [.command, .option], characters: "w"),
        table: table,
        numberJumpEnabled: false,
        reorderEnabled: false,
        filtering: false
      ) == .windowOperation(.closeWindow)
    )
    #expect(
      PanelKeyInput.action(
        for: optionPress(kVK_ANSI_W, [.option, .shift], characters: "W"),
        table: table,
        numberJumpEnabled: false,
        reorderEnabled: false,
        filtering: true
      ) == .windowOperation(.closeWindow)
    )
  }

  @Test
  func repeatedOptionWindowKeyAbsorbs() {
    #expect(
      PanelKeyInput.action(
        for: optionPress(kVK_ANSI_W, .option, repeating: true, characters: "w"),
        table: .defaults,
        numberJumpEnabled: false,
        reorderEnabled: false,
        filtering: false
      ) == .absorb
    )
  }

  @Test
  func optionWindowKeyWinsOverNumberJump() {
    #expect(
      PanelKeyInput.action(
        for: optionPress(kVK_ANSI_W, .option, characters: "w"),
        table: .defaults,
        numberJumpEnabled: true,
        reorderEnabled: false,
        filtering: false
      ) == .windowOperation(.closeWindow)
    )
  }

}
