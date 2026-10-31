import CoreGraphics
@testable import Lanterna
import Testing

// MARK: - FastSearchModifierTests

/// The modifiers Fast Search can start from: how each is spelled and named,
/// and how the flags of one event say which of them is held.
struct FastSearchModifierTests {

  // MARK: Internal

  @Test
  func spellingsAndNamesFollowTheFixedOrder() {
    #expect(FastSearchModifier.allCases.map(\.rawValue) == [
      "fn",
      "capsLock",
      "leftCommand",
      "rightCommand",
      "leftOption",
      "rightOption",
    ])
    #expect(FastSearchModifier.allCases.map(\.displayName) == [
      "Fn",
      "Caps Lock",
      "Left Command",
      "Right Command",
      "Left Option",
      "Right Option",
    ])
  }

  @Test
  func eachModifierReadsAsHeldOnItsOwn() {
    #expect(FastSearchModifier.heldAlone(flags: fn, escapeHeld: false) == .fn)
    #expect(FastSearchModifier.heldAlone(flags: leftCommand, escapeHeld: false) == .leftCommand)
    #expect(FastSearchModifier.heldAlone(flags: rightCommand, escapeHeld: false) == .rightCommand)
    #expect(FastSearchModifier.heldAlone(flags: leftOption, escapeHeld: false) == .leftOption)
    #expect(FastSearchModifier.heldAlone(flags: rightOption, escapeHeld: false) == .rightOption)
    #expect(FastSearchModifier.heldAlone(flags: [], escapeHeld: true) == .capsLock)
  }

  @Test
  func shiftDoesNotCount() {
    #expect(FastSearchModifier.heldAlone(flags: fn.union(shift), escapeHeld: false) == .fn)
    #expect(FastSearchModifier.heldAlone(flags: shift, escapeHeld: true) == .capsLock)
  }

  @Test
  func anythingBesidesOneModifierReadsAsNone() {
    #expect(FastSearchModifier.heldAlone(flags: [], escapeHeld: false) == nil)
    #expect(FastSearchModifier.heldAlone(flags: shift, escapeHeld: false) == nil)
    #expect(FastSearchModifier.heldAlone(flags: fn.union(control), escapeHeld: false) == nil)
    #expect(FastSearchModifier.heldAlone(flags: rightCommand.union(control), escapeHeld: false) == nil)
    #expect(FastSearchModifier.heldAlone(flags: fn.union(rightCommand), escapeHeld: false) == nil)
    #expect(FastSearchModifier.heldAlone(flags: leftCommand.union(rightCommand), escapeHeld: false) == nil)
    #expect(FastSearchModifier.heldAlone(flags: rightCommand.union(rightOption), escapeHeld: false) == nil)
    #expect(FastSearchModifier.heldAlone(flags: rightCommand, escapeHeld: true) == nil)
  }

  @Test
  func aCommandFlagWithNoSideReadsAsNone() {
    #expect(FastSearchModifier.heldAlone(flags: .maskCommand, escapeHeld: false) == nil)
    #expect(FastSearchModifier.heldAlone(flags: .maskAlternate, escapeHeld: false) == nil)
  }

  @Test
  func heldReadsEachModifierOnItsOwnBit() {
    #expect(FastSearchModifier.fn.isHeld(flags: fn.union(rightCommand), escapeHeld: false))
    #expect(FastSearchModifier.rightCommand.isHeld(flags: fn.union(rightCommand), escapeHeld: false))
    #expect(!FastSearchModifier.leftCommand.isHeld(flags: rightCommand, escapeHeld: false))
    #expect(!FastSearchModifier.leftOption.isHeld(flags: rightOption, escapeHeld: false))
    #expect(FastSearchModifier.capsLock.isHeld(flags: [], escapeHeld: true))
    #expect(!FastSearchModifier.capsLock.isHeld(flags: [], escapeHeld: false))
  }

  // MARK: Private

  private let fn = CGEventFlags.maskSecondaryFn
  private let shift = CGEventFlags.maskShift
  private let control = CGEventFlags.maskControl
  private let leftCommand = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
  private let rightCommand = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10)
  private let leftOption = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20)
  private let rightOption = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40)

}
