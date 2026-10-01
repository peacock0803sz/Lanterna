@testable import Lanterna
import Logging
import Synchronization
import Testing

/// Nothing is thinned on the way out: every level reaches stderr and the
/// mirror, and the log window is where lines are filtered.
struct DiagnosticsFilteringTests {

  /// swift-log ranks by severity: debug below info below warning
  /// below error. The log window's level floor reads the same order.
  @Test
  func levelsRankDebugBelowInfoBelowWarningBelowError() {
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

  /// At the level the process logger keeps, every level lands in both
  /// stderr and the mirror, debug included, in the order written.
  @Test
  func everyLevelReachesStderrAndTheMirror() {
    let emitted = Mutex([String]())
    let store = DiagnosticLogStore(emit: { text in emitted.withLock { $0.append(text) } })
    var logger = Logger(label: "filter-probe", factory: { _ in DiagnosticLogHandler(store: store) })
    logger.logLevel = Diagnostics.keptLevel
    logger.debug("filter-probe-debug")
    logger.info("filter-probe-info")
    logger.warning("filter-probe-warning")
    logger.error("filter-probe-error")
    let expected = ["filter-probe-debug", "filter-probe-info", "filter-probe-warning", "filter-probe-error"]
    #expect(store.recent.map(\.message) == expected)
    #expect(store.recent.map(\.level) == [.debug, .info, .warning, .error])
    #expect(emitted.withLock { $0 } == expected.map { $0 + "\n" })
  }

}
