@testable import Lanterna
import Logging
import Testing

/// The level order and the threshold meaning, pinned before the
/// mechanism that applies them. A change in what a threshold lets
/// through must show up here rather than slipping past silently.
struct DiagnosticsFilteringTests {
    /// swift-log ranks by severity: debug below info below warning
    /// below error. The threshold lets a line through when the line
    /// reaches it.
    @Test func levelsRankDebugBelowInfoBelowWarningBelowError() {
        #expect(Logger.Level.debug < .info)
        #expect(Logger.Level.info < .warning)
        #expect(Logger.Level.warning < .error)
        #expect(!(Logger.Level.debug < .debug))
        #expect(Logger.Level.error > .warning)
    }

    /// Only the four lowercase words read. Anything else, including
    /// swift-log's own `trace`, `notice` and `critical` and the old
    /// `warn` spelling, is for the caller to refuse as a whole.
    @Test(arguments: ["error", "warning", "info", "debug"])
    func theFourWordsParse(word: String) {
        #expect(Logger.Level.parse(word: word)?.rawValue == word)
    }

    @Test(arguments: ["Error", "WARN", "warn", " info", "info ", "trace", "notice", "critical", "", "verbose", "0"])
    func anythingElseRefuses(word: String) {
        #expect(Logger.Level.parse(word: word) == nil)
    }

    /// The command line wins where it says anything; the file covers
    /// the rest; silence on both means warnings and above.
    @Test func effectiveLevelPrefersTheCommandLineThenTheFile() {
        #expect(Logger.Level.effective(cli: .debug, file: .error) == .debug)
        #expect(Logger.Level.effective(cli: nil, file: .info) == .info)
        #expect(Logger.Level.effective(cli: nil, file: nil) == .warning)
    }

    /// Holds a store behind a logger, so a test can say what one
    /// threshold lets through without touching the process logger.
    private static func logger(threshold: Logger.Level, store: DiagnosticLogStore) -> Logger {
        var logger = Logger(label: "filter-probe", factory: { _ in DiagnosticLogHandler(store: store) })
        logger.logLevel = threshold
        return logger
    }

    /// At warnings, warnings and errors land while the ordinary flow
    /// and the test hook's lines go nowhere: not to the mirror, and
    /// spending none of the capacity either.
    @Test func warningsShowWhileInfoAndDebugGoNowhere() {
        let store = DiagnosticLogStore()
        let logger = Self.logger(threshold: .warning, store: store)
        logger.warning("filter-probe-warning")
        logger.error("filter-probe-error")
        logger.info("filter-probe-info")
        logger.debug("filter-probe-debug")
        #expect(store.recent.map(\.message) == ["filter-probe-warning", "filter-probe-error"])
    }

    /// Errors show under every threshold, warnings and above included.
    @Test func errorsShowUnderEveryThreshold() {
        for threshold in [Logger.Level.error, .warning, .info, .debug] as [Logger.Level] {
            let store = DiagnosticLogStore()
            let logger = Self.logger(threshold: threshold, store: store)
            logger.error("filter-probe-error")
            #expect(store.recent.map(\.message) == ["filter-probe-error"])
        }
    }

    /// Lowering the threshold brings the hidden lines back, in order.
    @Test func loweringTheThresholdRestoresTheHiddenLines() {
        let store = DiagnosticLogStore()
        let warning = Self.logger(threshold: .warning, store: store)
        warning.info("filter-probe-info")
        #expect(store.recent.isEmpty)
        let info = Self.logger(threshold: .info, store: store)
        info.info("filter-probe-info")
        info.debug("filter-probe-debug")
        #expect(store.recent.map(\.message) == ["filter-probe-info"])
    }
}
