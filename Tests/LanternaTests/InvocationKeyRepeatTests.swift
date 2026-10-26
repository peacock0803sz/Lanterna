import Foundation
@testable import Lanterna
import Testing

// MARK: - InvocationKeyRepeatTests

/// The hold decision, with no panel and no keyboard.
struct InvocationKeyRepeatTests {

  @Test
  func aForwardHoldArmsAndMoves() {
    #expect(InvocationKeyRepeat.shouldArm(role: .forward, panelStaysUpWalking: true))
    #expect(
      InvocationKeyRepeat.tick(keyIsDown: true, panelStillWalking: true, direction: .forward)
        == .move(.forward)
    )
  }

  @Test
  func aKeyThatCameUpStops() {
    #expect(
      InvocationKeyRepeat.tick(keyIsDown: false, panelStillWalking: true, direction: .forward)
        == .stop
    )
  }

  @Test
  func shiftWithCommandWalksBackward() {
    #expect(InvocationKeyRepeat.shouldArm(role: .backward, panelStaysUpWalking: true))
    let bindings = [
      InvocationKeyRepeat.Binding(
        keyCode: 48,
        modifiers: HeldModifiers(command: true),
        direction: .forward
      ),
      InvocationKeyRepeat.Binding(
        keyCode: 48,
        modifiers: HeldModifiers(shift: true, command: true),
        direction: .backward
      ),
    ]
    #expect(
      InvocationKeyRepeat.directionWhileHeld(
        bindings: bindings,
        keyCode: 48,
        held: HeldModifiers(command: true)
      ) == .forward
    )
    #expect(
      InvocationKeyRepeat.directionWhileHeld(
        bindings: bindings,
        keyCode: 48,
        held: HeldModifiers(shift: true, command: true)
      ) == .backward
    )
  }

  @Test
  func filterAndAClosingPanelDoNotArm() {
    #expect(!InvocationKeyRepeat.shouldArm(role: .filter, panelStaysUpWalking: true))
    #expect(!InvocationKeyRepeat.shouldArm(role: .forward, panelStaysUpWalking: false))
    #expect(
      InvocationKeyRepeat.tick(keyIsDown: true, panelStillWalking: false, direction: .forward)
        == .stop
    )
    #expect(
      InvocationKeyRepeat.tick(keyIsDown: true, panelStillWalking: true, direction: nil) == .stop
    )
  }

  @Test
  func secondsPassThroughAndOutOfRangeValuesClamp() {
    let timing = InvocationKeyRepeat.timing(initialDelay: .seconds(1), interval: .seconds(0.1))
    #expect(timing.initialDelay == .seconds(1))
    #expect(timing.interval == .seconds(0.1))
    let negativeDelay = InvocationKeyRepeat.timing(
      initialDelay: .seconds(-1),
      interval: .seconds(0.1)
    )
    #expect(negativeDelay.initialDelay == .zero)
    let zeroInterval = InvocationKeyRepeat.timing(initialDelay: .seconds(1), interval: .zero)
    #expect(zeroInterval.interval == .milliseconds(1))
    let negativeInterval = InvocationKeyRepeat.timing(
      initialDelay: .seconds(1),
      interval: .seconds(-1)
    )
    #expect(negativeInterval.interval == .milliseconds(1))
    let remainder = InvocationKeyRepeat.timing(
      initialDelay: .seconds(1) - .seconds(0.4),
      interval: .seconds(0.1)
    )
    #expect(remainder.initialDelay == .seconds(0.6))
    let overshot = InvocationKeyRepeat.timing(
      initialDelay: .seconds(0.2) - .seconds(1),
      interval: .seconds(0.1)
    )
    #expect(overshot.initialDelay == .zero)
  }

  @Test
  func theRepeatFollowsTheKeyThatWasPressed() {
    let bindings = [
      InvocationKeyRepeat.Binding(
        keyCode: 42,
        modifiers: HeldModifiers(command: true),
        direction: .forward
      )
    ]
    #expect(
      InvocationKeyRepeat.directionWhileHeld(
        bindings: bindings,
        keyCode: 42,
        held: HeldModifiers(command: true)
      ) == .forward
    )
    #expect(
      InvocationKeyRepeat.directionWhileHeld(
        bindings: bindings,
        keyCode: 48,
        held: HeldModifiers(command: true)
      ) == nil
    )
  }

}
