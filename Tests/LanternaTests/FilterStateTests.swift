import CoreGraphics
@testable import Lanterna
import Testing

/// The memory a filtering appearance keeps, held without any panel.
///
/// Every case here runs against identities made by hand (data-model.md):
/// what was chosen and what matches is decided by the test, never by
/// watching real keystrokes.
struct FilterStateTests {
    private let first = WindowItem.Identifier(windowID: 1)
    private let second = WindowItem.Identifier(windowID: 2)
    private let third = WindowItem.Identifier(windowID: 3)

    private var all: [WindowItem.Identifier] {
        [first, second, third]
    }

    /// Every appearance starts empty, remembering nothing.
    @Test func everyAppearanceStartsEmpty() {
        let state = FilterState()
        #expect(state.query.isEmpty)
        #expect(state.rememberedID == nil)
    }

    /// Typing appends to the query.
    @Test func typingAppendsToTheQuery() {
        var state = FilterState()
        state.append("a")
        state.append("b")
        #expect(state.query == "ab")
    }

    /// Backspace removes the last character; on an empty query it does nothing.
    @Test func backspaceRemovesTheLastCharacter() {
        var state = FilterState()
        state.append("ab")
        state.removeLast()
        #expect(state.query == "a")
        state.removeLast()
        state.removeLast()
        #expect(state.query.isEmpty)
    }

    /// Clearing drops the query and the memory; the next appearance starts over.
    @Test func clearingDropsBothQueryAndMemory() {
        var state = FilterState(previousMatchedIDs: Set(all))
        state.append("a")
        _ = state.resolveSelection(matched: [second], incoming: first)
        state.clear()
        #expect(state.query.isEmpty)
        #expect(state.rememberedID == nil)
    }

    /// Losing the chosen row moves to the first match and remembers the lost row.
    @Test func losingTheChosenRowSelectsTheFirstMatch() {
        var state = FilterState(previousMatchedIDs: Set(all))
        let chosen = state.resolveSelection(matched: [second, third], incoming: first)
        #expect(chosen == second)
        #expect(state.rememberedID == first)
    }

    /// Shortening back onto the remembered row restores it.
    @Test func shorteningBackOntoTheRememberedRowRestoresIt() {
        var state = FilterState(previousMatchedIDs: Set(all))
        _ = state.resolveSelection(matched: [second, third], incoming: first)
        let chosen = state.resolveSelection(matched: all, incoming: second)
        #expect(chosen == first)
    }

    /// Narrowing further after moving with the arrows keeps the arrowed row.
    @Test func narrowingAfterMovingKeepsTheArrowedRow() {
        var state = FilterState(previousMatchedIDs: Set(all))
        _ = state.resolveSelection(matched: [second, third], incoming: first)
        _ = state.resolveSelection(matched: all, incoming: first)
        let chosen = state.resolveSelection(matched: [first, third], incoming: third)
        #expect(chosen == third)
    }

    /// Passing through an empty match keeps the memory for the way back.
    @Test func passingThroughAnEmptyMatchKeepsTheMemory() {
        var state = FilterState(previousMatchedIDs: Set(all))
        _ = state.resolveSelection(matched: [second], incoming: first)
        let none = state.resolveSelection(matched: [], incoming: nil)
        #expect(none == nil)
        #expect(state.rememberedID == first)
        let chosen = state.resolveSelection(matched: all, incoming: nil)
        #expect(chosen == first)
    }
}
