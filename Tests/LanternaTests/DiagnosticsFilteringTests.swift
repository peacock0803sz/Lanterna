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

    /// A fresh store starts quiet: warnings and above show, the
    /// ordinary flow does not.
    @Test func aFreshStoreWarnsByDefault() {
        let store = DiagnosticLogStore()
        #expect(store.threshold == .warn)
        store.write("filter-probe-warn", level: .warn)
        store.write("filter-probe-info", level: .info)
        #expect(store.recent.map(\.message) == ["filter-probe-warn"])
    }

    /// Below the threshold, a line goes nowhere: not to the mirror,
    /// and it spends none of the capacity either.
    @Test func belowThresholdLinesSpendNoCapacity() {
        let store = DiagnosticLogStore()
        store.threshold = .error
        for index in 0 ..< DiagnosticLog.capacity {
            store.write("filter-flood-\(index)", level: .info)
        }
        #expect(store.recent.isEmpty)
        store.write("filter-probe-error", level: .error)
        #expect(store.recent.map(\.message) == ["filter-probe-error"])
    }

    /// Errors show under every threshold, warnings and above included.
    @Test func errorsShowUnderEveryThreshold() {
        for threshold in [LogLevel.error, .warn, .info, .debug] {
            let store = DiagnosticLogStore()
            store.threshold = threshold
            store.write("filter-probe-error", level: .error)
            #expect(store.recent.map(\.message) == ["filter-probe-error"])
        }
    }

    /// Lowering the threshold brings the hidden lines back, in order.
    @Test func loweringTheThresholdRestoresTheHiddenLines() {
        let store = DiagnosticLogStore()
        store.write("filter-probe-info", level: .info)
        #expect(store.recent.isEmpty)
        store.threshold = .info
        store.write("filter-probe-info", level: .info)
        store.write("filter-probe-debug", level: .debug)
        #expect(store.recent.map(\.message) == ["filter-probe-info"])
    }
}
