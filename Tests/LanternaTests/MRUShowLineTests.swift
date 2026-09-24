@testable import Lanterna
import Testing

/// The recent-use evidence the show line carries, and nothing else.
///
/// The first row drawn and where the order came from, pinned the way the
/// timing is: readers grep the prefix to count appearances, so the evidence
/// goes at the end where nothing is counting from. An empty list names no
/// first row rather than the row that is not there.
///
/// A file of its own because the measurement suites it would have joined are
/// already long enough that adding to them would put them over the file
/// limit.
struct MRUShowLineTests {
    private static func measurement(
        firstID: WindowItem.Identifier?,
        source: MRUTracker.NewestSource
    ) -> HotkeyMeasurement {
        HotkeyMeasurement(
            combination: .forward,
            elapsed: .microseconds(4800),
            entryCount: 12,
            deliveryDelay: nil,
            gatheredOnDemand: false,
            becameKey: false,
            mru: MRUSummary(firstID: firstID, source: source)
        )
    }

    @Test func committedFirstRowIsNamedWithItsSource() {
        #expect(
            Self.measurement(
                firstID: WindowItem.Identifier(windowID: 42),
                source: .commit
            ).summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries)"
                + "; not taking keys (they reach the frontmost application)"
                + "; mru first (window 42) via commit"
        )
    }

    @Test func externalSourceNamesItself() {
        #expect(
            Self.measurement(
                firstID: WindowItem.Identifier(windowID: 7),
                source: .external
            ).summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries)"
                + "; not taking keys (they reach the frontmost application)"
                + "; mru first (window 7) via external"
        )
    }

    @Test func emptyListNamesNoFirstRow() {
        #expect(
            Self.measurement(firstID: nil, source: .none).summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries)"
                + "; not taking keys (they reach the frontmost application)"
                + "; mru first none via none"
        )
    }
}
