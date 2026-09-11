import Foundation
@testable import Lanterna
import Testing

private typealias Failure = HotkeyRegistrationOutcome.Failure

/// Registration itself needs Carbon and a running application, so this line is
/// the only account of it anyone gets. It is pinned wording by wording.
struct HotkeyRegistrationOutcomeTests {
    /// Chosen because it is what a real refusal looks like; the number itself
    /// carries no meaning here beyond being printed back verbatim.
    private static let refusal: OSStatus = -9878

    private static func failure(_ combination: HotkeyCombination) -> Failure {
        Failure(combination: combination, status: refusal)
    }

    private static let everything = HotkeyRegistrationOutcome(
        registered: HotkeyCombination.all,
        failures: []
    )

    private static let onlyReverse = HotkeyRegistrationOutcome(
        registered: [.reverse],
        failures: [failure(.forward)]
    )

    private static let nothing = HotkeyRegistrationOutcome(
        registered: [],
        failures: HotkeyCombination.all.map(failure)
    )

    @Test func bothTakenReadsAsOneList() {
        #expect(Self.everything.summaryLine == "registered Cmd+Tab, Shift+Cmd+Tab")
        #expect(Self.everything.isTotalFailure == false)
    }

    /// A half-working app is the case worth reading carefully: it keeps
    /// running, so the log is all that says why one key does nothing.
    @Test func oneRefusalSitsBesideTheOneThatWorked() {
        #expect(
            Self.onlyReverse.summaryLine
                == "registered Shift+Cmd+Tab; could not register Cmd+Tab (error -9878)"
        )
        #expect(Self.onlyReverse.isTotalFailure == false)
    }

    @Test func nothingTakenSaysWhyAndSaysItIsLeaving() {
        #expect(
            Self.nothing.summaryLine
                == "could not register Cmd+Tab (error -9878), "
                + "Shift+Cmd+Tab (error -9878); no hotkey registered, exiting"
        )
        #expect(Self.nothing.isTotalFailure)
    }

    /// Every combination lands on exactly one of the two lists. A combination
    /// on neither would go missing from the line without anything noticing.
    ///
    /// The initialiser is what enforces this: a malformed outcome traps there
    /// rather than failing an expectation here. This is kept because it
    /// states the invariant at the type's boundary, and because it is still a
    /// check in a release test build, where the assert is compiled out.
    @Test(arguments: [everything, onlyReverse, nothing])
    func theTwoListsTogetherAccountForEveryCombination(outcome: HotkeyRegistrationOutcome) {
        let accounted = outcome.registered.map(\.id) + outcome.failures.map(\.combination.id)
        #expect(accounted.count == HotkeyCombination.all.count)
        #expect(Set(accounted) == Set(HotkeyCombination.all.map(\.id)))
    }
}
