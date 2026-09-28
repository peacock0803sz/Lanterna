import AppKit
import Foundation
@testable import Lanterna
import Testing

/// What the shortcut memory keeps while the process runs.
///
/// The gating against the shown list and the current matcher lives with
/// the keeper (`PanelFilter`); what is settled here is the table itself:
/// recording, lookup, overwriting, the length cap, and the key folding.
struct ShortcutMemoryTests {
    private func id(_ windowID: UInt32) -> WindowItem.Identifier {
        WindowItem.Identifier(windowID: CGWindowID(windowID))
    }

    @Test func recordsAndLooksUpOneQuery() {
        var memory = ShortcutMemory(maxLength: 5)
        #expect(memory.lookup(query: "m") == nil)
        memory.record(query: "m", id: id(7))
        #expect(memory.lookup(query: "m") == id(7))
    }

    @Test func newerCommitWins() {
        var memory = ShortcutMemory(maxLength: 5)
        memory.record(query: "m", id: id(7))
        memory.record(query: "m", id: id(9))
        #expect(memory.lookup(query: "m") == id(9))
    }

    @Test func keysIgnoreCase() {
        var memory = ShortcutMemory(maxLength: 5)
        memory.record(query: "M", id: id(7))
        #expect(memory.lookup(query: "m") == id(7))
        #expect(memory.lookup(query: "M") == id(7))
    }

    @Test func queriesDoNotLeakAcrossKeys() {
        var memory = ShortcutMemory(maxLength: 5)
        memory.record(query: "m", id: id(7))
        #expect(memory.lookup(query: "ma") == nil)
    }

    @Test func emptyQueryIsNeverRecorded() {
        var memory = ShortcutMemory(maxLength: 5)
        memory.record(query: "", id: id(7))
        #expect(memory.lookup(query: "") == nil)
    }

    @Test func overlongQueriesAreOutOfScope() {
        var memory = ShortcutMemory(maxLength: 1)
        memory.record(query: "mail", id: id(7))
        #expect(memory.lookup(query: "mail") == nil)
        memory.record(query: "m", id: id(7))
        #expect(memory.lookup(query: "m") == id(7))
    }

    @Test func zeroCapBehavesAsEmpty() {
        var memory = ShortcutMemory(maxLength: 0)
        memory.record(query: "m", id: id(7))
        #expect(memory.lookup(query: "m") == nil)
    }
}
