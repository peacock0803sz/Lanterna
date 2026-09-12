@testable import Lanterna
import Testing

/// The panel appearing quickly is the whole point of the feature, and this
/// line is the only record of whether it did, so its shape is pinned segment
/// by segment.
struct HotkeyMeasurementTests {
    private static func measurement(
        combination: HotkeyCombination = .forward,
        elapsed: Duration = .microseconds(4800),
        entryCount: Int = 12,
        deliveryDelay: Duration? = nil,
        gatheredOnDemand: Bool = false
    ) -> HotkeyMeasurement {
        HotkeyMeasurement(
            combination: combination,
            elapsed: elapsed,
            entryCount: entryCount,
            deliveryDelay: deliveryDelay,
            gatheredOnDemand: gatheredOnDemand
        )
    }

    /// No run produces this shape today: the delivery reading comes from two
    /// readings of one clock, neither of which can fail, so it is always
    /// there. It stays optional, and tested, so that if the reading ever does
    /// become fallible the line loses a segment instead of losing its meaning.
    @Test func withNothingOptionalTheLineIsTheTimingAlone() {
        #expect(
            Self.measurement().summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries)"
        )
    }

    @Test func aMeasuredDeliveryFollowsTheTiming() {
        #expect(
            Self.measurement(deliveryDelay: .microseconds(1900)).summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries); delivery 1.9 ms"
        )
    }

    /// A reading taken while the list was still being gathered says more about
    /// the list than about the panel, so it is marked rather than averaged in
    /// with the rest.
    @Test func gatheringOnTheSpotIsCalledOut() {
        #expect(
            Self.measurement(gatheredOnDemand: true).summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries)"
                + "; gathered on the spot (no list held yet)"
        )
    }

    @Test func bothOptionalSegmentsKeepTheirOrder() {
        #expect(
            Self.measurement(deliveryDelay: .microseconds(1900), gatheredOnDemand: true)
                .summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries); delivery 1.9 ms"
                + "; gathered on the spot (no list held yet)"
        )
    }

    @Test func theReverseCombinationNamesItself() {
        #expect(
            Self.measurement(combination: .reverse).summaryLine
                == "panel shown 4.8 ms after Shift+Cmd+Tab (12 entries)"
        )
    }

    /// Both timings round to one decimal place, so the budget can be read off
    /// the line without arithmetic.
    @Test func timingsCarryExactlyOneDecimalPlace() {
        let line = Self.measurement(
            elapsed: .microseconds(71251),
            deliveryDelay: .zero
        ).summaryLine
        #expect(line == "panel shown 71.3 ms after Cmd+Tab (12 entries); delivery 0.0 ms")
    }
}
