import Foundation
@testable import Lanterna
import Testing

/// What taking a row came to, written as the commit line's pair.
///
/// The wording lives beside the code that decides it, the way the exit lines
/// do above. What is pinned here is every reason word for word, so a change
/// to any of them turns red here rather than in a count taken downstream.
@MainActor
struct SwitchMeasurementTests {

  // MARK: Internal

  @Test
  func aTakeSaysWhereItWent() {
    #expect(
      Self.measurement(.switched).summaryLine
        == "switched to TextEdit — Untitled (window 42) 4.8 ms after Command was released"
    )
  }

  @Test
  func eachFailureNamesItselfInFixedWords() {
    #expect(
      Self.measurement(.failed(.windowGone)).summaryLine
        == "could not switch to TextEdit — Untitled (window 42) (window gone) "
        + "4.8 ms after Command was released"
    )
    #expect(
      Self.measurement(.failed(.applicationGone)).summaryLine
        == "could not switch to TextEdit — Untitled (window 42) (application gone) "
        + "4.8 ms after Command was released"
    )
    #expect(
      Self.measurement(.failed(.timedOut)).summaryLine
        == "could not switch to TextEdit — Untitled (window 42) (timed out) 4.8 ms after Command was released"
    )
    #expect(
      Self.measurement(.failed(.other(reason: "activation refused"))).summaryLine
        == "could not switch to TextEdit — Untitled (window 42) (activation refused) "
        + "4.8 ms after Command was released"
    )
  }

  /// The pair keeps the trigger's wording on both lines.
  @Test
  func theTakeKeepsTheKeyCommitWording() {
    #expect(
      Self.measurement(.switched, by: .commitKey(.returnKey)).summaryLine
        == "switched to TextEdit — Untitled (window 42) 4.8 ms after Return"
    )
    #expect(
      Self.measurement(.switched, by: .commitKey(.keypadEnter)).summaryLine
        == "switched to TextEdit — Untitled (window 42) 4.8 ms after keypad Enter"
    )
  }

  /// A reason holding newlines still prints as one line, and a reason with
  /// nothing to say falls back rather than printing an empty pair of
  /// parentheses.
  @Test
  func aReasonPrintsAsOneLineOrFallsBack() {
    #expect(
      Self.measurement(.failed(.other(reason: "first\nsecond"))).summaryLine
        == "could not switch to TextEdit — Untitled (window 42) (first second) "
        + "4.8 ms after Command was released"
    )
    #expect(
      Self.measurement(.failed(.other(reason: "   "))).summaryLine
        == "could not switch to TextEdit — Untitled (window 42) (unknown) 4.8 ms after Command was released"
    )
  }

  /// A note beside the result reads in fixed words, and a line without
  /// one reads exactly as before. The reasons are flattened to one line
  /// like the failure reasons are.
  @Test
  func aNoteReadsBesideTheResultInFixedWords() {
    #expect(
      Self.measurement(.switched, reopen: .requested).summaryLine
        == "switched to TextEdit — Untitled (window 42) (reopen requested) "
        + "4.8 ms after Command was released"
    )
    #expect(
      Self.measurement(.switched, reopen: .skippedNoBundle).summaryLine
        == "switched to TextEdit — Untitled (window 42) (reopen skipped (no bundle)) "
        + "4.8 ms after Command was released"
    )
    #expect(
      Self.measurement(.switched, raiseAlone: .held).summaryLine
        == "switched to TextEdit — Untitled (window 42) (raised alone) "
        + "4.8 ms after Command was released"
    )
    #expect(
      Self.measurement(.switched, raiseAlone: .notHeld(reason: "main window error -25205")).summaryLine
        == "switched to TextEdit — Untitled (window 42) "
        + "(raised alone, not held (main window error -25205)) 4.8 ms after Command was released"
    )
    #expect(
      Self.measurement(.switched, raiseAlone: .notHeld(reason: "first\nsecond")).summaryLine
        == "switched to TextEdit — Untitled (window 42) "
        + "(raised alone, not held (first second)) 4.8 ms after Command was released"
    )
  }

  // MARK: Private

  private static func measurement(
    _ outcome: ActivationOutcome,
    by trigger: PanelExitMeasurement.Trigger = .commandRelease,
    reopen: ReopenNote? = nil,
    raiseAlone: RaiseAloneNote? = nil
  ) -> SwitchMeasurement {
    SwitchMeasurement(
      appName: "TextEdit",
      displayTitle: "Untitled",
      id: WindowItem.Identifier(windowID: 42),
      outcome: outcome,
      trigger: trigger,
      elapsed: .microseconds(4800),
      reopen: reopen,
      raiseAlone: raiseAlone
    )
  }

}
