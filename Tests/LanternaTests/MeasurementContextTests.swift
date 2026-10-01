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

  // MARK: Private

  private static func measurement(outcome: ActivationOutcome) -> SwitchMeasurement {
    SwitchMeasurement(
      appName: "Vivaldi",
      displayTitle: "Lanterna",
      id: WindowItem.Identifier(windowID: 42),
      outcome: outcome,
      trigger: .commandRelease,
      elapsed: .microseconds(1_012_400)
    )
  }

}
