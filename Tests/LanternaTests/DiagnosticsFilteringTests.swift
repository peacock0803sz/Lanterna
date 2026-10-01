@testable import Lanterna
import Logging
import Testing

/// Every line is recorded without gating; the window query filters what shows.
/// The order below still decides how level comparisons rank rows.
struct DiagnosticsFilteringTests {

  // MARK: Internal

  /// swift-log ranks by severity: debug below info below warning
  /// below error. The query language compares levels in this order.
  @Test
  func levelsRankDebugBelowInfoBelowWarningBelowError() {
    #expect(Logger.Level.debug < .info)
    #expect(Logger.Level.info < .warning)
    #expect(Logger.Level.warning < .error)
    #expect(!(Logger.Level.debug < .debug))
    #expect(Logger.Level.error > .warning)
  }

  /// With the most verbose setting every word lands in the mirror in order.
  /// Nothing is gated away; filtering happens through window queries alone.
  @Test
  func everyWordIsRecordedWithoutGating() {
    let store = DiagnosticLogStore()
    let logger = Self.logger(store: store)
    logger.debug("filter-probe-debug")
    logger.info("filter-probe-info")
    logger.warning("filter-probe-warning")
    logger.error("filter-probe-error")
    #expect(store.recent.map(\.message) == [
      "filter-probe-debug",
      "filter-probe-info",
      "filter-probe-warning",
      "filter-probe-error",
    ])
    #expect(store.recent.map(\.level) == [.debug, .info, .warning, .error])
  }

  // MARK: Private

  /// Holds a store behind a logger at the most verbose setting,
  /// without touching the process logger.
  private static func logger(store: DiagnosticLogStore) -> Logger {
    var logger = Logger(label: "filter-probe", factory: { _ in DiagnosticLogHandler(store: store) })
    logger.logLevel = .trace
    return logger
  }

}
