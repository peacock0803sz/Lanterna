@testable import Lanterna
import Testing

/// The millisecond figure is what the manual acceptance check reads off the
/// summary line to check the timing criteria, so the conversion is pinned term
/// by term.
struct DiagnosticsTests {
    /// A pass that runs past a second must show its seconds too: with the
    /// seconds term dropped, a timed-out application's 1004.8 ms would print
    /// 4.8 and every other case would still pass.
    @Test(arguments: [
        (Duration.milliseconds(1004.8), "1004.8"),
        (.zero, "0.0"),
        (.seconds(2), "2000.0"),
        (.microseconds(1500), "1.5"),
        (.microseconds(71249), "71.2"),
        (.microseconds(71251), "71.3"),
    ])
    func millisecondsTextRoundsToOneDecimalPlace(duration: Duration, text: String) {
        #expect(Diagnostics.millisecondsText(duration) == text)
    }
}
