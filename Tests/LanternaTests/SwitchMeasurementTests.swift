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
    private static func measurement(
        _ outcome: ActivationOutcome,
        by trigger: PanelExitMeasurement.Trigger = .commandRelease
    ) -> SwitchMeasurement {
        SwitchMeasurement(
            appName: "TextEdit",
            displayTitle: "Untitled",
            id: WindowItem.Identifier(windowID: 42),
            outcome: outcome,
            trigger: trigger,
            elapsed: .microseconds(4800)
        )
    }

    @Test func aTakeSaysWhereItWent() {
        #expect(
            Self.measurement(.switched).summaryLine
                == "switched to TextEdit — Untitled (window 42) 4.8 ms after Command was released"
        )
    }

    @Test func eachFailureNamesItselfInFixedWords() {
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
    @Test func theTakeKeepsTheKeyCommitWording() {
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
    @Test func aReasonPrintsAsOneLineOrFallsBack() {
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
}
