import AppKit
import Carbon.HIToolbox
import Testing
@testable import Lanterna

struct HotkeyBindingTests {
  @Test
  func defaultsKeepLegacyNamesAndIDs() {
    let bindings = HotkeyBinding.defaults
    #expect(bindings.count == 5)
    #expect(bindings.map(\.name) == ["Cmd+Tab", "Shift+Cmd+Tab", "Cmd+Space", "Opt+Tab", "Shift+Opt+Tab"])
    #expect(bindings.map(\.combination) == [.forward, .reverse, .filter, .parallelForward, .parallelReverse])
  }

  @Test
  func customKeysChangeCodesAndNames() {
    var table = KeyBindingTable.defaults
    table.keys[.show] = [ResolvedKey(keyCode: UInt16(kVK_Space), modifiers: .control)]
    let bindings = HotkeyBinding.bindings(for: table)
    let show = bindings.first { $0.combination == .forward }
    #expect(show?.keyCode == UInt32(kVK_Space))
    #expect(show?.carbonModifiers == UInt32(controlKey))
    #expect(show?.name == "Ctrl+Space")
  }

  @Test
  func extraKeysTakeFurtherSlots() {
    var table = KeyBindingTable.defaults
    table.keys[.show] = [
      ResolvedKey(keyCode: UInt16(kVK_Tab), modifiers: .command),
      ResolvedKey(keyCode: UInt16(kVK_Space), modifiers: .control),
    ]
    let bindings = HotkeyBinding.bindings(for: table)
    let show = bindings.filter { $0.combination == .forward }
    #expect(show.count == 2)
    #expect(Set(show.map(\.eventID)).count == 2)
  }
}
