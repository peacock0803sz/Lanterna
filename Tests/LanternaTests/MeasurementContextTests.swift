@testable import Lanterna
import Testing

/// The values a switch line carries beside its wording. The keys are what
/// the log window offers as columns, so their names and types are pinned.
struct MeasurementContextTests {

  // MARK: Internal

  @Test
  func aTimedOutSwitchCarriesTheTargetAndTheFigure() {
    let context = Self.measurement(outcome: .failed(.timedOut))
      .context(processIdentifier: 8123, bundle: "com.vivaldi.Vivaldi")
    #expect(context == [
      "app": .string("Vivaldi"),
      "bundle": .string("com.vivaldi.Vivaldi"),
      "pid": .int(8123),
      "window": .string("Lanterna"),
      "windowId": .string("0x2a"),
      "result": .string("timedOut"),
      "ms": .int(1012),
    ])
  }

  @Test
  func theBundleIsLeftOutWhenTheRowWasNotFound() {
    let context = Self.measurement(outcome: .switched).context(processIdentifier: 1, bundle: nil)
    #expect(context["bundle"] == nil)
    #expect(context["result"] == .string("ok"))
  }

  @Test
  func anyOtherFailureReadsAsFailed() {
    let context = Self.measurement(outcome: .failed(.windowGone)).context(processIdentifier: 1, bundle: nil)
    #expect(context["result"] == .string("failed"))
  }

  @Test
  func millisecondsRoundToTheNearestWhole() {
    #expect(Diagnostics.wholeMilliseconds(.microseconds(1499)) == 1)
    #expect(Diagnostics.wholeMilliseconds(.microseconds(1500)) == 2)
  }

  /// The switch notes travel as keys only when present, leaving the
  /// long-standing keys untouched either way.
  @Test
  func theNotesTravelAsKeysOnlyWhenPresent() {
    let noted = Self.measurement(outcome: .switched, reopen: .requested, raiseAlone: .held)
      .context(processIdentifier: 1, bundle: nil)
    #expect(noted["reopen"] == .string("requested"))
    #expect(noted["raiseAlone"] == .string("held"))
    #expect(noted["result"] == .string("ok"))
    #expect(noted["ms"] == .int(1012))

    let plain = Self.measurement(outcome: .switched).context(processIdentifier: 1, bundle: nil)
    #expect(plain["reopen"] == nil)
    #expect(plain["raiseAlone"] == nil)
    #expect(plain["result"] == .string("ok"))
  }

  /// The other note words map to their own context words, leaving the
  /// long-standing keys untouched too.
  @Test
  func theOtherNotesMapToTheirOwnContextWords() {
    let noted = Self.measurement(
      outcome: .switched,
      reopen: .skippedNoBundle,
      raiseAlone: .notHeld(reason: "main window error -25205")
    ).context(processIdentifier: 1, bundle: nil)
    #expect(noted["reopen"] == .string("skippedNoBundle"))
    #expect(noted["raiseAlone"] == .string("notHeld"))
    #expect(noted["result"] == .string("ok"))
    #expect(noted["ms"] == .int(1012))
  }

  // MARK: Private

  private static func measurement(
    outcome: ActivationOutcome,
    reopen: ReopenNote? = nil,
    raiseAlone: RaiseAloneNote? = nil
  ) -> SwitchMeasurement {
    SwitchMeasurement(
      appName: "Vivaldi",
      displayTitle: "Lanterna",
      id: WindowItem.Identifier(windowID: 42),
      outcome: outcome,
      trigger: .commandRelease,
      elapsed: .microseconds(1_012_400),
      reopen: reopen,
      raiseAlone: raiseAlone
    )
  }

}
