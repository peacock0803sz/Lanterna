@testable import Lanterna
import Testing

/// The level order and the threshold meaning, pinned before the
/// mechanism that applies them. A reorder of the words must show up
/// here rather than silently moving what a threshold lets through.
struct DiagnosticsFilteringTests {
    /// The ranking the threshold compares by: errors first, then
    /// warnings, then the ordinary flow, then the test hook's lines.
    @Test func levelsRankErrorBelowWarnBelowInfoBelowDebug() {
        #expect(LogLevel.error < .warn)
        #expect(LogLevel.warn < .info)
        #expect(LogLevel.info < .debug)
        #expect(!(LogLevel.debug < .debug))
        #expect(LogLevel.debug > .error)
    }

    /// Only the four lowercase words read. Anything else is for the
    /// caller to refuse as a whole.
    @Test(arguments: ["error", "warn", "info", "debug"])
    func theFourWordsParse(word: String) {
        #expect(LogLevel.parse(word)?.rawValue == word)
    }

    @Test(arguments: ["Error", "WARN", " info", "info ", "warning", "", "verbose", "0"])
    func anythingElseRefuses(word: String) {
        #expect(LogLevel.parse(word) == nil)
    }

    /// The command line wins where it says anything; the file covers
    /// the rest; silence on both means warnings and above.
    @Test func effectiveLevelPrefersTheCommandLineThenTheFile() {
        #expect(LogLevel.effective(cli: .debug, file: .error) == .debug)
        #expect(LogLevel.effective(cli: nil, file: .info) == .info)
        #expect(LogLevel.effective(cli: nil, file: nil) == .warn)
    }
}
