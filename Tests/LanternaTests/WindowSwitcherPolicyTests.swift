import ApplicationServices
import Foundation
@testable import Lanterna
import Testing

// MARK: - WindowSwitcherPolicyTests

/// What the commit switches change about a take.
///
/// The old path stays the default: with both switches off the seam hears
/// exactly what it always heard. An engaged switch adds one call in one
/// place, and the report says what that call came to.
@MainActor
struct WindowSwitcherPolicyTests {

  // MARK: Internal

  /// An engaged opening switch asks once after a take that came forward,
  /// and the take carries what the asking came to.
  @Test
  func anEngagedOpeningSwitchAsksOnceAfterComingForward() {
    let peer = ScriptedAccessibility(windowCount: 0)
    let report = peer.switcher().switchTo(application(), policy: engaged())

    #expect(report == ActivationReport(outcome: .switched, reopen: .requested, raiseAlone: nil))
    #expect(peer.operationNames == ["activate", "reopen"])
    #expect(peer.reopenPIDs == [4242])
  }

  /// A missing bundle keeps the take and says which half did not happen.
  @Test
  func aMissingBundleKeepsTheTakeWithItsNote() {
    let peer = ScriptedAccessibility(windowCount: 0)
    peer.reopenAnswer = .skippedNoBundle
    let report = peer.switcher().switchTo(application(), policy: engaged())

    #expect(report == ActivationReport(outcome: .switched, reopen: .skippedNoBundle, raiseAlone: nil))
    #expect(peer.operationNames == ["activate", "reopen"])
  }

  /// A take that never came forward opens nothing and notes nothing: the
  /// failure is the whole answer, in the old words.
  @Test(arguments: [
    (LiveWindowSwitcher.ApplicationActivation.missing, ActivationFailure.applicationGone),
    (.refused, .other(reason: "activation refused")),
  ])
  func aTakeThatNeverCameForwardOpensNothing(
    answer: LiveWindowSwitcher.ApplicationActivation,
    failure: ActivationFailure
  ) {
    let peer = ScriptedAccessibility(windowCount: 0)
    peer.activateAnswer = answer
    let report = peer.switcher().switchTo(application(), policy: engaged())

    #expect(report == ActivationReport(outcome: .failed(failure), reopen: nil, raiseAlone: nil))
    #expect(peer.operationNames == ["activate"])
    #expect(peer.reopenPIDs.isEmpty)
  }

  /// Disengaged, a windowless take is only brought forward, in the old
  /// words with no notes.
  @Test
  func aDisengagedWindowlessTakeOnlyComesForward() {
    let peer = ScriptedAccessibility(windowCount: 0)
    let report = peer.switcher().switchTo(application(), policy: .off)

    #expect(report == ActivationReport(outcome: .switched, reopen: nil, raiseAlone: nil))
    #expect(peer.operationNames == ["activate"])
    #expect(peer.reopenPIDs.isEmpty)
  }

  /// An engaged opening switch leaves a window take alone: the order is
  /// the old activate, unminimize, raise, and no note rides along.
  @Test
  func anEngagedOpeningSwitchLeavesAWindowTakeAlone() {
    let peer = ScriptedAccessibility(windowCount: 2)
    let report = peer.switcher().switchTo(window(), policy: engaged())

    #expect(report == ActivationReport(outcome: .switched, reopen: nil, raiseAlone: nil))
    #expect(peer.operationNames == ["activate", "unminimize", "raise"])
    #expect(peer.reopenPIDs.isEmpty)
  }

  // MARK: Private

  private func engaged() -> ActivationPolicy {
    ActivationPolicy(reopensWindowlessApps: true, raisesOnlyChosenWindow: false)
  }

  private func application() -> ActivationTarget {
    ActivationTarget(
      id: .application(4242),
      ownerProcessIdentifier: 4242,
      appName: "Music",
      displayTitle: "Music"
    )
  }

  private func window(windowID: CGWindowID = 101) -> ActivationTarget {
    ActivationTarget(
      id: WindowItem.Identifier(windowID: windowID),
      ownerProcessIdentifier: 4242,
      appName: "TextEdit",
      displayTitle: "Untitled"
    )
  }

}
