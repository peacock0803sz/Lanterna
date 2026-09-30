import AppKit
import Darwin
@testable import Lanterna
import Testing

// MARK: - OwnWindowSwitcherTests

/// What the own-process decorator takes itself and what it hands on.
///
/// No real windows: the two seams answer from a script, so a closed
/// settings window and a refused activation are both staged without
/// putting either on screen.
@MainActor
struct OwnWindowSwitcherTests {

  // MARK: Internal

  /// A closed own window ends the take before the wrapped switcher is
  /// asked: the row is gone, not erroneous.
  @Test
  func missingOwnWindowIsWindowGone() {
    let script = ScriptedOwn(activateAnswer: true, showAnswer: false)
    let wrapped = FakeWindowSwitcher()
    let outcome = switcher(script: script, wrapped: wrapped).switchTo(target(pid: 123))

    #expect(outcome == .failed(.windowGone))
    #expect(script.activateCalls == [true])
    #expect(script.showCalls == [7])
    #expect(wrapped.targets.isEmpty)
  }

  /// A present own window is activated and then shown, and nothing is
  /// handed on.
  @Test
  func presentOwnWindowIsSwitched() {
    let script = ScriptedOwn(activateAnswer: true, showAnswer: true)
    let wrapped = FakeWindowSwitcher()
    let outcome = switcher(script: script, wrapped: wrapped).switchTo(target(pid: 123))

    #expect(outcome == .switched)
    #expect(script.activateCalls == [true])
    #expect(script.showCalls == [7])
    #expect(wrapped.targets.isEmpty)
  }

  /// A refused activation names itself and shows nothing: raising a
  /// window of a process that would not come forward is not attempted.
  @Test
  func refusedActivationNamesItself() {
    let script = ScriptedOwn(activateAnswer: false, showAnswer: true)
    let wrapped = FakeWindowSwitcher()
    let outcome = switcher(script: script, wrapped: wrapped).switchTo(target(pid: 123))

    #expect(outcome == .failed(.other(reason: "activation refused")))
    #expect(script.activateCalls == [true])
    #expect(script.showCalls.isEmpty)
    #expect(wrapped.targets.isEmpty)
  }

  /// Any other process is the wrapped switcher's business: the seams
  /// stay untouched and its answer stands.
  @Test
  func otherProcessDelegatesWrappedOutcome() {
    let script = ScriptedOwn(activateAnswer: true, showAnswer: true)
    let wrapped = FakeWindowSwitcher()
    wrapped.outcomes = [.failed(.timedOut)]
    let outcome = switcher(script: script, wrapped: wrapped).switchTo(target(pid: 999))

    #expect(outcome == .failed(.timedOut))
    #expect(script.activateCalls.isEmpty)
    #expect(script.showCalls.isEmpty)
    #expect(wrapped.targets.count == 1)
  }

  // MARK: Private

  private func target(pid: pid_t, windowID: CGWindowID = 7) -> ActivationTarget {
    ActivationTarget(
      id: WindowItem.Identifier(windowID: windowID),
      ownerProcessIdentifier: pid,
      appName: "Lanterna",
      displayTitle: "Lanterna Settings"
    )
  }

  private func switcher(
    script: ScriptedOwn,
    wrapped: FakeWindowSwitcher,
    pid: pid_t = 123
  ) -> OwnWindowSwitcher {
    OwnWindowSwitcher(
      wrapped: wrapped,
      ownProcessIdentifier: pid,
      activateApp: { script.activate($0) },
      showWindow: { script.show($0) }
    )
  }

}

// MARK: - ScriptedOwn

/// Scripted answers for the own-process seams, recording every call.
///
/// A box rather than bare closures so the calls can be read back after
/// the take. Driven synchronously on the main actor, like the decorator
/// that calls it.
// swiftlint:disable:next no_unchecked_sendable - test-only; driven synchronously on the main actor
private final class ScriptedOwn: @unchecked Sendable {

  // MARK: Lifecycle

  init(activateAnswer: Bool, showAnswer: Bool) {
    self.activateAnswer = activateAnswer
    self.showAnswer = showAnswer
  }

  // MARK: Internal

  private(set) var activateCalls = [Bool]()
  private(set) var showCalls = [CGWindowID]()
  var activateAnswer: Bool
  var showAnswer: Bool

  func activate(_ ignoringOtherApps: Bool) -> Bool {
    activateCalls.append(ignoringOtherApps)
    return activateAnswer
  }

  func show(_ windowID: CGWindowID) -> Bool {
    showCalls.append(windowID)
    return showAnswer
  }

}
