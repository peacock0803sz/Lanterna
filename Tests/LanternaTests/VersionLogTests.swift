@testable import Lanterna
import Testing

/// The on-screen version and the bundle version agree by one rule: the full
/// describe string minus its leading `v` equals the short version. Anything
/// else — a commit past the tag, a dirty tree, a missing `v` — does not match.
struct VersionLogTests {
    @Test(arguments: [
        ("v1.2.3", "1.2.3", true),
        ("v0.1.0", "0.1.0", true),
        ("v1.2.3-4-gdeadbee", "1.2.3", false),
        ("v1.2.3-dirty", "1.2.3", false),
        ("v1.2.3-4-gdeadbee-dirty", "1.2.3", false),
        ("1.2.3", "1.2.3", false),
        ("v1.2.3", "1.2.4", false),
        ("v1.2.3", "", false),
    ])
    func onlyACleanTagMatchesItsShortVersion(full: String, short: String, matches: Bool) {
        #expect(VersionMatch.matches(full: full, short: short) == matches)
    }

    /// The cap is a contract value, not a tuning knob left to the
    /// implementation. A run longer than this keeps the newest entries.
    @Test func theRingHoldsFiveHundredLines() {
        #expect(DiagnosticLog.capacity == 500)
    }
}
