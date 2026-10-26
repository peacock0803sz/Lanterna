import ApplicationServices
import Foundation
@testable import Lanterna
import Testing

// MARK: - WindowSwitcherTests

/// What the seam sends, and what it does with each answer.
///
/// Which error an application returns is the whole behaviour under test, and
/// no live application can be asked to return one, so a stand-in answers
/// instead. The stand-in records every call, because resolving must not be
/// skipped: the target handed over has to be the element acted upon.
///
/// The shape mirrors `FakeApplication`: an `@unchecked Sendable` peer driven
/// synchronously on one thread, with a clock the answers advance.
@MainActor
struct WindowSwitcherTests {

  // MARK: Internal

  /// A resolved element is the one acted upon, and the owning pid is the
  /// one asked about. Anything else would take a row nobody chose.
  @Test
  func resolvingHandsTheResolvedElementToTheOperations() {
    let peer = ScriptedAccessibility(windowCount: 2)
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .switched)
    #expect(peer.activatePIDs == [4242])
    #expect(peer.minimizeValues == [false])
    #expect(peer.createPIDs == [4242])
    #expect(peer.operated == [peer.identity(of: 1), peer.identity(of: 1)])
  }

  /// A row for a window on another Space is not in the list, and is
  /// found through the probe instead.
  @Test
  func aWindowOnAnotherSpaceResolvesThroughTheProbe() {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.otherSpaceIndices = [1]
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .switched)
    #expect(peer.operated == [peer.identity(of: 1), peer.identity(of: 1)])
  }

  /// A missing row ends the take before anything is touched.
  @Test
  func anUnknownIDFailsWithoutTouchingAnything() {
    let peer = ScriptedAccessibility(windowCount: 2)
    let outcome = peer.switcher().switchTo(target(windowID: 999))

    #expect(outcome == .failed(.windowGone))
    #expect(peer.operationNames.isEmpty)
  }

  /// A slow refusal to answer is a wait.
  @Test
  func aSlowWindowsReadBecomesTimedOut() {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.windowsError = .cannotComplete
    peer.listCost = .milliseconds(600)
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .failed(.timedOut))
    #expect(peer.operationNames.isEmpty)
  }

  /// A fast refusal is about the application, not the wait.
  @Test
  func aFastWindowsReadBecomesApplicationGone() {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.windowsError = .cannotComplete
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .failed(.applicationGone))
    #expect(peer.operationNames.isEmpty)
  }

  /// Which error ends a resolve, spelled out.
  @Test(arguments: [
    (AXError.apiDisabled, ActivationFailure.other(reason: "permission missing")),
    (.invalidUIElement, .applicationGone),
    (.failure, .other(reason: "error \(AXError.failure.rawValue)")),
  ])
  func aWindowsReadErrorMapsToItsOutcome(error: AXError, failure: ActivationFailure) {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.windowsError = error
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .failed(failure))
    #expect(peer.operationNames.isEmpty)
  }

  /// No application, no take; a refusal names itself.
  @Test
  func aMissingApplicationIsGoneAndARefusalSaysSo() {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.activateAnswer = .missing
    #expect(peer.switcher().switchTo(target()) == .failed(.applicationGone))
    #expect(peer.operationNames == ["activate"])

    peer.activateAnswer = .refused
    #expect(peer.switcher().switchTo(target()) == .failed(.other(reason: "activation refused")))
    #expect(peer.operationNames == ["activate", "activate"])
  }

  /// A timeout that cannot even be set is about the application.
  @Test
  func anUnsettableTimeoutIsApplicationGone() {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.timeoutResult = .cannotComplete
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .failed(.applicationGone))
    #expect(peer.operationNames.isEmpty)
  }

  /// Element-level answers sort the same way application-level ones do: a
  /// slow silence is a wait, a fast one the application going away.
  @Test(arguments: [
    (Duration.zero, ActivationFailure.applicationGone),
    (.milliseconds(600), .timedOut),
  ])
  func anElementIDSilenceSortsByItsWait(cost: Duration, failure: ActivationFailure) {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.idAnswers = [0: (.success, 100), 1: (.cannotComplete, 0)]
    peer.idCost = cost
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .failed(failure))
    #expect(peer.operationNames.isEmpty)
  }

  /// An earlier wait must not condemn a later refusal. The ceiling judges
  /// one message, not the running total.
  @Test
  func anAccumulatedWaitDoesNotCondemnAFastRefusal() {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.listCost = .milliseconds(600)
    peer.idAnswers = [0: (.success, 100), 1: (.cannotComplete, 0)]
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .failed(.applicationGone))
    #expect(peer.operationNames.isEmpty)
  }

  /// Every element is given its own timeout before its first message: the
  /// setting rides with the element it protects.
  @Test
  func everyElementIsGivenItsOwnTimeout() {
    let peer = ScriptedAccessibility(windowCount: 2)
    _ = peer.switcher().switchTo(target())

    #expect(peer.prepared == [peer.appIdentity(), peer.identity(of: 0), peer.identity(of: 1)])
  }

  /// An element that cannot take a timeout is skipped like anything else
  /// unreadable. A target never matched is windowGone, while the other
  /// window still takes.
  @Test
  func anUnpreparableElementIsSkipped() {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.prepareErrors = [1: .failure]
    #expect(peer.switcher().switchTo(target()) == .failed(.windowGone))

    peer.prepareErrors = [0: .failure]
    #expect(peer.switcher().switchTo(target()) == .switched)
  }

  /// A list that is not a list names itself, in the reader's words.
  @Test
  func aMalformedListNamesItself() {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.malformedList = true
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .failed(.other(reason: "malformed answer")))
    #expect(peer.operationNames.isEmpty)
  }

  /// No open windows reads as an empty list: the row is gone, not
  /// erroneous. Closing an application's last window between showing and
  /// taking is the ordinary way to arrive here.
  @Test
  func anEmptyWindowListIsWindowGone() {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.windowsError = .noValue
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .failed(.windowGone))
    #expect(peer.operationNames.isEmpty)
  }

  /// A write that never comes back is a wait; any other write error names
  /// itself. Either way the take ends there: later operations are not
  /// called on a window the take has already failed.
  @Test(arguments: [
    (Duration.zero, ActivationFailure.other(reason: "error \(AXError.cannotComplete.rawValue)")),
    (.milliseconds(600), .timedOut),
  ])
  func aWriteErrorEndsTheTakeWithItsOutcome(cost: Duration, failure: ActivationFailure) {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.writeError = .cannotComplete
    peer.writeCost = cost
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .failed(failure))
    #expect(peer.operationNames == ["activate", "unminimize"])
  }

  /// A refused raise names its code and calls nothing after itself,
  /// because nothing comes after it.
  @Test
  func aRefusedRaiseNamesItsCode() {
    let peer = ScriptedAccessibility(windowCount: 2)
    peer.raiseError = .failure
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .failed(.other(reason: "error \(AXError.failure.rawValue)")))
    #expect(peer.operationNames == ["activate", "unminimize", "raise"])
  }

  /// The full order, pinned: activate, then unminimize, then raise. The
  /// order is the design's answer to a hidden and minimized window, so a
  /// rewrite putting it back the other way round must turn red here.
  /// Unminimizing is written without asking first, so the order holds
  /// whether or not the window was minimized.
  @Test
  func theOperationsRunActivateUnminimizeRaise() {
    let peer = ScriptedAccessibility(windowCount: 2)
    let outcome = peer.switcher().switchTo(target())

    #expect(outcome == .switched)
    #expect(peer.operationNames == ["activate", "unminimize", "raise"])
  }

  /// An application with no window is only brought forward: there is no
  /// window to look for, unminimize or raise.
  @Test
  func anApplicationRowOnlyActivates() {
    let peer = ScriptedAccessibility(windowCount: 0)
    let application = ActivationTarget(
      id: .application(4242),
      ownerProcessIdentifier: 4242,
      appName: "Music",
      displayTitle: "Music"
    )
    #expect(peer.switcher().switchTo(application) == .switched)
    #expect(peer.operationNames == ["activate"])
    #expect(peer.createPIDs.isEmpty)

    peer.activateAnswer = .missing
    #expect(peer.switcher().switchTo(application) == .failed(.applicationGone))
  }

  // MARK: Private

  private func target(windowID: CGWindowID = 101) -> ActivationTarget {
    ActivationTarget(
      id: WindowItem.Identifier(windowID: windowID),
      ownerProcessIdentifier: 4242,
      appName: "TextEdit",
      displayTitle: "Untitled"
    )
  }

}
