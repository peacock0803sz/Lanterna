import Foundation
import Logging
import Testing
@testable import Lanterna

private typealias Failure = HotkeyRegistrationOutcome.Failure

// MARK: - HotkeyRegistrationOutcomeTests

/// Registration itself needs Carbon and a running application, so this line is
/// the only account of it anyone gets. It is pinned wording by wording.
struct HotkeyRegistrationOutcomeTests {

  // MARK: Internal

  @Test
  func allTakenReadsAsOneList() {
    #expect(Self.everything
      .summaryLine ==
      "registered Cmd+Tab (main), Shift+Cmd+Tab (main), Cmd+Space (main), Opt+Tab (parallel), Shift+Opt+Tab (parallel)")
    #expect(Self.everything.isTotalFailure == false)
    #expect(Self.everything.logLevel == .info)
  }

  /// A half-working app is the case worth reading carefully: it keeps
  /// running, so the log is all that says why one key does nothing.
  @Test
  func oneRefusalSitsBesideTheOnesThatWorked() {
    #expect(
      Self.allButForward.summaryLine
        == "registered Shift+Cmd+Tab (main), Cmd+Space (main), Opt+Tab (parallel), Shift+Opt+Tab (parallel); could not register Cmd+Tab (main) (error -9878)"
    )
    #expect(Self.allButForward.isTotalFailure == false)
    #expect(Self.allButForward.logLevel == .warning)
  }

  @Test
  func nothingTakenSaysWhyAndSaysItIsLeaving() {
    #expect(
      Self.nothing.summaryLine
        == "could not register Cmd+Tab (main) (error -9878), "
        + "Shift+Cmd+Tab (main) (error -9878), Cmd+Space (main) (error -9878), Opt+Tab (parallel) (error -9878), "
        + "Shift+Opt+Tab (parallel) (error -9878); no hotkey registered, exiting"
    )
    #expect(Self.nothing.isTotalFailure)
    #expect(Self.nothing.logLevel == .error)
  }

  /// Every combination lands on exactly one of the two lists. A combination
  /// on neither would go missing from the line without anything noticing.
  ///
  /// The initialiser is what enforces this: a malformed outcome traps there
  /// rather than failing an expectation here. This is kept because it
  /// states the invariant at the type's boundary, and because it is still a
  /// check in a release test build, where the assert is compiled out.
  @Test(arguments: [everything, allButForward, nothing])
  func theTwoListsTogetherAccountForEveryCombination(outcome: HotkeyRegistrationOutcome) {
    let accounted = outcome.registered.map(\.id) + outcome.failures.map(\.combination.id)
    #expect(accounted.count == HotkeyCombination.all.count)
    #expect(Set(accounted) == Set(HotkeyCombination.all.map(\.id)))
  }

  // MARK: Private

  /// Chosen because it is what a real refusal looks like; the number itself
  /// carries no meaning here beyond being printed back verbatim.
  private static let refusal: OSStatus = -9878

  private static let everything = HotkeyRegistrationOutcome(
    registered: HotkeyCombination.all,
    failures: []
  )

  private static let allButForward = HotkeyRegistrationOutcome(
    registered: [.reverse, .filter, .parallelForward, .parallelReverse],
    failures: [failure(.forward)]
  )

  private static let nothing = HotkeyRegistrationOutcome(
    registered: [],
    failures: HotkeyCombination.all.map(failure)
  )

  private static func failure(_ combination: HotkeyCombination) -> Failure {
    Failure(combination: combination, status: refusal)
  }

}
