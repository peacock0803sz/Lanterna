import ApplicationServices
import Foundation
@testable import Lanterna
import Testing

// MARK: - WindowSwitcherPolicyTests

/// What the commit switches change about a take.
///
/// With the commit switches off the seam hears only the default
/// activating calls. An engaged switch adds its own calls to the
/// take, and the report says what they came to.
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
    #expect(peer.activatePIDs == [4242])
    #expect(peer.createPIDs.isEmpty)
    #expect(peer.minimizeValues.isEmpty)
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
    #expect(peer.createPIDs.isEmpty)
  }

  /// A take that never came forward opens nothing and notes nothing: the
  /// failure is the whole answer, worded as with the switch off.
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

  /// Disengaged, a windowless take is only brought forward, with no notes.
  @Test
  func aDisengagedWindowlessTakeOnlyComesForward() {
    let peer = ScriptedAccessibility(windowCount: 0)
    let report = peer.switcher().switchTo(application(), policy: .off)

    #expect(report == ActivationReport(outcome: .switched, reopen: nil, raiseAlone: nil))
    #expect(peer.operationNames == ["activate"])
    #expect(peer.createPIDs.isEmpty)
    #expect(peer.reopenPIDs.isEmpty)
  }

  /// An engaged opening switch leaves a window take alone: the order is
  /// the default activate, unminimize, raise, and no note rides along.
  @Test
  func anEngagedOpeningSwitchLeavesAWindowTakeAlone() {
    let peer = ScriptedAccessibility(windowCount: 2)
    let report = peer.switcher().switchTo(window(), policy: engaged())

    #expect(report == ActivationReport(outcome: .switched, reopen: nil, raiseAlone: nil))
    #expect(peer.operationNames == ["activate", "unminimize", "raise"])
    #expect(peer.reopenPIDs.isEmpty)
  }

  /// An engaged suppression takes the chosen window through the longer
  /// order, every step on the chosen element, and the take carries that
  /// the procedure held.
  @Test
  func anEngagedSuppressionRaisesAloneInOrder() {
    let peer = ScriptedAccessibility(windowCount: 2)
    let report = peer.switcher().switchTo(window(), policy: suppression())

    #expect(report == ActivationReport(outcome: .switched, reopen: nil, raiseAlone: .held))
    #expect(peer.operationNames == ["setMain", "raise", "activate", "unminimize", "raise"])
    #expect(peer.activatePIDs == [4242])
    #expect(peer.minimizeValues == [false])
    #expect(peer.createPIDs == [4242])
    #expect(peer.operated == [peer.identity(of: 1), peer.identity(of: 1), peer.identity(of: 1), peer.identity(of: 1)])
  }

  /// A faltering preparation still switches: the note names the first
  /// step that gave way and its cause.
  @Test
  func aFalteringPreparationStillSwitchesWithItsNote() {
    let main = ScriptedAccessibility(windowCount: 2)
    main.setMainError = .failure
    let mainReport = main.switcher().switchTo(window(), policy: suppression())

    #expect(
      mainReport
        == ActivationReport(
          outcome: .switched,
          reopen: nil,
          raiseAlone: .notHeld(reason: "main window error \(AXError.failure.rawValue)")
        )
    )
    #expect(main.operationNames == ["setMain", "raise", "activate", "unminimize", "raise"])

    let raised = ScriptedAccessibility(windowCount: 2)
    raised.raiseErrors = [.failure]
    let raiseReport = raised.switcher().switchTo(window(), policy: suppression())

    #expect(
      raiseReport
        == ActivationReport(
          outcome: .switched,
          reopen: nil,
          raiseAlone: .notHeld(reason: "raise error \(AXError.failure.rawValue)")
        )
    )
    #expect(raised.operationNames == ["setMain", "raise", "activate", "unminimize", "raise"])
  }

  /// Past the preparations a failure fails the take itself, worded as
  /// with the switch off and carrying no note.
  @Test
  func pastThePreparationsTheDefaultFailuresStand() {
    let refused = ScriptedAccessibility(windowCount: 2)
    refused.activateAnswer = .refused
    #expect(
      refused.switcher().switchTo(window(), policy: suppression())
        == ActivationReport(outcome: .failed(.other(reason: "activation refused")), reopen: nil, raiseAlone: nil)
    )
    #expect(refused.operationNames == ["setMain", "raise", "activate"])

    let stuck = ScriptedAccessibility(windowCount: 2)
    stuck.writeError = .failure
    stuck.raiseError = .success
    #expect(
      stuck.switcher().switchTo(window(), policy: suppression())
        == ActivationReport(
          outcome: .failed(.other(reason: "error \(AXError.failure.rawValue)")),
          reopen: nil,
          raiseAlone: nil
        )
    )
    #expect(stuck.operationNames == ["setMain", "raise", "activate", "unminimize"])

    let dropped = ScriptedAccessibility(windowCount: 2)
    dropped.raiseErrors = [nil, .failure]
    #expect(
      dropped.switcher().switchTo(window(), policy: suppression())
        == ActivationReport(
          outcome: .failed(.other(reason: "error \(AXError.failure.rawValue)")),
          reopen: nil,
          raiseAlone: nil
        )
    )
    #expect(dropped.operationNames == ["setMain", "raise", "activate", "unminimize", "raise"])
  }

  /// A row that resolves to nothing writes nothing: the failure comes
  /// before any preparation.
  @Test
  func anUnresolvableRowWritesNothing() {
    let peer = ScriptedAccessibility(windowCount: 2)
    let report = peer.switcher().switchTo(window(windowID: 999), policy: suppression())

    #expect(report == ActivationReport(outcome: .failed(.windowGone), reopen: nil, raiseAlone: nil))
    #expect(peer.operationNames.isEmpty)
  }

  /// Disengaged, a window take runs the default order with no preparation.
  @Test
  func aDisengagedWindowTakeRunsTheDefaultOrder() {
    let peer = ScriptedAccessibility(windowCount: 2)
    let report = peer.switcher().switchTo(window(), policy: .off)

    #expect(report == ActivationReport(outcome: .switched, reopen: nil, raiseAlone: nil))
    #expect(peer.operationNames == ["activate", "unminimize", "raise"])
  }

  /// Suppression leaves a windowless take alone: the preparation never
  /// runs for such a row, and no note rides along.
  @Test
  func suppressionLeavesAWindowlessTakeAlone() {
    let peer = ScriptedAccessibility(windowCount: 0)
    let report = peer.switcher().switchTo(application(), policy: suppression())

    #expect(report == ActivationReport(outcome: .switched, reopen: nil, raiseAlone: nil))
    #expect(peer.operationNames == ["activate"])
    #expect(peer.createPIDs.isEmpty)
  }

  /// Both switches engaged, a windowless take still only reopens: the
  /// raising preparation never runs for such a row.
  @Test
  func bothSwitchesEngagedWindowlessTakeStillReopens() {
    let peer = ScriptedAccessibility(windowCount: 0)
    let report = peer.switcher().switchTo(application(), policy: both())

    #expect(report == ActivationReport(outcome: .switched, reopen: .requested, raiseAlone: nil))
    #expect(peer.operationNames == ["activate", "reopen"])
  }

  /// Both switches engaged, a window take still raises alone through the
  /// longer order, and the take carries that the procedure held.
  @Test
  func bothSwitchesEngagedWindowTakeStillRaisesAlone() {
    let peer = ScriptedAccessibility(windowCount: 2)
    let report = peer.switcher().switchTo(window(), policy: both())

    #expect(report == ActivationReport(outcome: .switched, reopen: nil, raiseAlone: .held))
    #expect(peer.operationNames == ["setMain", "raise", "activate", "unminimize", "raise"])
  }

  // MARK: Private

  private func engaged() -> ActivationPolicy {
    ActivationPolicy(reopensWindowlessApps: true, raisesOnlyChosenWindow: false)
  }

  private func suppression() -> ActivationPolicy {
    ActivationPolicy(reopensWindowlessApps: false, raisesOnlyChosenWindow: true)
  }

  private func both() -> ActivationPolicy {
    ActivationPolicy(reopensWindowlessApps: true, raisesOnlyChosenWindow: true)
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
