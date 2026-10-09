import Carbon.HIToolbox
@testable import Lanterna
import Testing

private func stroke(_ keyCode: Int, repeating: Bool) -> PanelKeystroke {
  PanelKeystroke(
    keyCode: UInt16(keyCode),
    modifiers: [],
    isARepeat: repeating,
    characters: "s"
  )
}

// MARK: - KeyRepeatSwallowTests

struct KeyRepeatSwallowTests {
  @Test
  func heldRepeatIsSwallowed() {
    var swallow = KeyRepeatSwallow()
    swallow.hold(UInt16(kVK_ANSI_S))
    let swallowed = swallow.swallows(stroke(kVK_ANSI_S, repeating: true))
    #expect(swallowed)
  }

  @Test
  func otherKeyRepeatIsNotSwallowed() {
    var swallow = KeyRepeatSwallow()
    swallow.hold(UInt16(kVK_ANSI_S))
    let swallowed = swallow.swallows(stroke(kVK_ANSI_D, repeating: true))
    #expect(!swallowed)
  }

  @Test
  func freshPressClearsTheMemory() {
    var swallow = KeyRepeatSwallow()
    swallow.hold(UInt16(kVK_ANSI_S))
    let first = swallow.swallows(stroke(kVK_ANSI_S, repeating: false))
    #expect(!first)
    let second = swallow.swallows(stroke(kVK_ANSI_S, repeating: true))
    #expect(!second)
  }

  @Test
  func resetClearsTheMemory() {
    var swallow = KeyRepeatSwallow()
    swallow.hold(UInt16(kVK_ANSI_S))
    swallow.reset()
    let swallowed = swallow.swallows(stroke(kVK_ANSI_S, repeating: true))
    #expect(!swallowed)
  }

  @Test
  func nothingHeldSwallowsNothing() {
    var swallow = KeyRepeatSwallow()
    let swallowed = swallow.swallows(stroke(kVK_ANSI_S, repeating: true))
    #expect(!swallowed)
  }
}
