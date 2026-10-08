import AppKit
import Foundation
@testable import Lanterna
import Testing

/// The shortcut memory stops growing: past the entry cap the
/// longest-ago recorded query leaves first.
struct ShortcutMemoryCapTests {

  // MARK: Internal

  @Test
  func pastTheCapTheOldestRecordedLeavesFirst() {
    var memory = ShortcutMemory(maxLength: 10, maxEntries: 3)
    memory.record(query: "aaa", id: id(1))
    memory.record(query: "bbb", id: id(2))
    memory.record(query: "ccc", id: id(3))
    memory.record(query: "ddd", id: id(4))
    #expect(memory.entries.count == 3)
    #expect(memory.lookup(query: "aaa") == nil)
    #expect(memory.lookup(query: "bbb") == id(2))
    #expect(memory.lookup(query: "ccc") == id(3))
    #expect(memory.lookup(query: "ddd") == id(4))
  }

  @Test
  func recordingAgainKeepsARowNewest() {
    var memory = ShortcutMemory(maxLength: 10, maxEntries: 2)
    memory.record(query: "aaa", id: id(1))
    memory.record(query: "bbb", id: id(2))
    memory.record(query: "aaa", id: id(3))
    memory.record(query: "ccc", id: id(4))
    #expect(memory.lookup(query: "bbb") == nil)
    #expect(memory.lookup(query: "aaa") == id(3))
    #expect(memory.lookup(query: "ccc") == id(4))
  }

  @Test
  func overwritingWithoutGrowingKeepsEveryRow() {
    var memory = ShortcutMemory(maxLength: 10, maxEntries: 2)
    memory.record(query: "aaa", id: id(1))
    memory.record(query: "bbb", id: id(2))
    memory.record(query: "aaa", id: id(9))
    #expect(memory.entries.count == 2)
    #expect(memory.lookup(query: "aaa") == id(9))
    #expect(memory.lookup(query: "bbb") == id(2))
  }

  @Test
  func outOfScopeQueriesTakeNoRoom() {
    var memory = ShortcutMemory(maxLength: 1, maxEntries: 1)
    memory.record(query: "toolong", id: id(1))
    memory.record(query: "a", id: id(2))
    #expect(memory.entries.count == 1)
    #expect(memory.lookup(query: "a") == id(2))
  }

  // MARK: Private

  private func id(_ windowID: UInt32) -> WindowItem.Identifier {
    WindowItem.Identifier(windowID: CGWindowID(windowID))
  }

}
