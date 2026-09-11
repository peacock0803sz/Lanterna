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

    /// Pinned to the literals, not to each other: these two numbers are what
    /// the system is actually asked for, and nothing else in the suite would
    /// notice them changing. The relation below would still hold for any key
    /// and any base modifier, while the app went on logging "Cmd+Tab" and
    /// taking the system's own Cmd+Tab away.
    @Test func forwardIsTabWithCommandAndNothingElse() {
        #expect(HotkeyCombination.forward.keyCode == UInt32(kVK_Tab))
        #expect(HotkeyCombination.forward.carbonModifiers == UInt32(cmdKey))
    }

    /// The reverse combination differs from the forward one by exactly Shift,
    /// on the same key. Stated as a relation because this is the only thing
    /// holding the two together: the literals above pin the forward one, and
    /// nothing but this would notice the reverse one drifting away from it.
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
