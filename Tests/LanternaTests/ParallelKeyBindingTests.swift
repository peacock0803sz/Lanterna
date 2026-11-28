import AppKit
import Carbon.HIToolbox
import Testing
@testable import Lanterna

private func key(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> ResolvedKey {
  ResolvedKey(keyCode: UInt16(keyCode), modifiers: modifiers)
}

private func raw(_ keyCode: Int, _ modifiers: String...) -> RawKeyBinding {
  RawKeyBinding(keyCode: keyCode, modifiers: modifiers)
}

// MARK: - ParallelKeyBindingTests

/// The parallel invocations' defaults and their modifier rule: beside the
/// main three, holding Option, and never holding neither Command nor Option.
struct ParallelKeyBindingTests {

  @Test
  func parallelDefaultsStandBesideTheMainOnes() {
    #expect(KeyBindingTable.defaults[.showParallel] == [key(kVK_Tab, .option)])
    #expect(KeyBindingTable.defaults[.showParallelReverse] == [key(kVK_Tab, [.option, .shift])])
  }

  @Test
  func defaultKeysDoNotOverlap() {
    let table = KeyBindingTable.defaults
    var holders = [ResolvedKey: [KeyBindingAction]]()
    for action in KeyBindingAction.allCases {
      for key in table[action] {
        holders[key, default: []].append(action)
      }
    }
    let overlaps = holders.values.filter { $0.count > 1 }
    for actions in overlaps {
      #expect(actions.count == 2)
      #expect(KeyBindingResolver.isExcusedPair(actions[0], actions[1]))
    }
  }

  @Test
  func parallelKeysNeedCommandOrOption() {
    #expect(KeyBindingTable.allows(modifiers: .option, for: .showParallel))
    #expect(KeyBindingTable.allows(modifiers: .command, for: .showParallel))
    #expect(KeyBindingTable.allows(modifiers: [.command, .option], for: .showParallelReverse))
    #expect(KeyBindingTable.allows(modifiers: [.control, .option], for: .showParallel))
    #expect(!KeyBindingTable.allows(modifiers: [], for: .showParallel))
    #expect(!KeyBindingTable.allows(modifiers: .control, for: .showParallel))
    #expect(!KeyBindingTable.allows(modifiers: .shift, for: .showParallelReverse))
    #expect(!KeyBindingTable.allows(modifiers: [.control, .shift], for: .showParallel))
  }

  @Test
  func mainKeysKeepTheLooserRule() {
    #expect(KeyBindingTable.allows(modifiers: .control, for: .show))
    #expect(KeyBindingTable.allows(modifiers: [.control, .shift], for: .showReverse))
  }

  @Test
  func parallelKeysWithoutCommandOrOptionFallBack() {
    let (table, issues) = KeyBindingResolver.resolve(
      [.showParallel: [raw(kVK_Tab, "ctrl")]],
      order: [.showParallel]
    )
    #expect(table[.showParallel] == KeyBindingTable.defaults[.showParallel])
    #expect(issues.count == 1)
    #expect(issues[0].action == .showParallel)
    #expect(issues[0].reason == .invalid)
  }

  @Test
  func emptiedParallelRowsRefillWithDefaults() {
    let (table, issues) = KeyBindingResolver.resolve([.showParallel: []], order: [])
    #expect(table[.showParallel] == KeyBindingTable.defaults[.showParallel])
    #expect(issues.isEmpty)
  }

  @Test
  func customizedParallelDisplacesUntouchedMainDefault() {
    let (table, issues) = KeyBindingResolver.resolve(
      [.showParallel: [raw(kVK_Tab, "cmd")]],
      order: [.showParallel]
    )
    #expect(table[.showParallel] == [key(kVK_Tab, .command)])
    #expect(!table[.show].contains(key(kVK_Tab, .command)))
    #expect(issues.contains(where: { $0.action == .show && $0.reason == .conflict }))
  }

  @Test
  func customizedMainDisplacesParallelDefault() {
    let (table, issues) = KeyBindingResolver.resolve(
      [.show: [raw(kVK_Tab, "opt")]],
      order: [.show]
    )
    #expect(table[.show] == [key(kVK_Tab, .option)])
    #expect(!table[.showParallel].contains(key(kVK_Tab, .option)))
    #expect(issues.contains(where: { $0.action == .showParallel && $0.reason == .conflict }))
  }

}
