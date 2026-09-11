import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// The identifier is the only thing that survives the trip through Carbon and
/// back, so the round trip is what keeps a press from being attributed to the
/// wrong combination.
struct HotkeyCombinationTests {
    @Test(arguments: HotkeyCombination.all)
    func everyCombinationSurvivesTheRoundTrip(combination: HotkeyCombination) {
        #expect(HotkeyCombination(id: combination.id) == combination)
    }

    @Test func identifiersAreUniqueAndNonZero() {
        let identifiers = HotkeyCombination.all.map(\.id)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.allSatisfy { $0 != 0 })
    }

    @Test(arguments: [0, 3, 99, UInt32.max] as [UInt32])
    func anIdentifierThisAppNeverHandedOutIsRejected(identifier: UInt32) {
        #expect(HotkeyCombination(id: identifier) == nil)
    }

    /// The manual acceptance checks grep the diagnostics for these two
    /// spellings, so they are pinned rather than derived.
    @Test func namesReadTheWayTheDiagnosticsDo() {
        #expect(HotkeyCombination.forward.name == "Cmd+Tab")
        #expect(HotkeyCombination.reverse.name == "Shift+Cmd+Tab")
    }

    /// Both are Tab, and the reverse one is the forward one plus Shift. Stated
    /// as a relation rather than as two literals, so a swapped table fails
    /// here instead of at the keyboard.
    @Test func reverseIsForwardPlusShiftOnTheSameKey() {
        #expect(HotkeyCombination.reverse.keyCode == HotkeyCombination.forward.keyCode)
        #expect(
            HotkeyCombination.reverse.carbonModifiers
                == HotkeyCombination.forward.carbonModifiers | UInt32(shiftKey)
        )
    }

    @Test func allIsEveryCase() {
        #expect(HotkeyCombination.all == HotkeyCombination.allCases)
    }
}
