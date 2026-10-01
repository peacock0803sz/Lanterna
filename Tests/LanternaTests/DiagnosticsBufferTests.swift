@testable import Lanterna
import Logging
import Testing

// MARK: - DiagnosticsBufferTests

/// The ring keeps a mirror of every emitted line without changing the lines
/// themselves. Each test holds its own store and fills past the cap, so no
/// long-lived process and no racing with other suites.
struct DiagnosticsBufferTests {
  @Test
  func writingPastTheCapKeepsTheNewestFiveHundred() {
    let store = DiagnosticLogStore()
    let total = DiagnosticLog.capacity + 1
    for index in 0 ..< total {
      store.append("buffer-probe-\(index)")
    }
    let recent = store.recent
    #expect(recent.count == DiagnosticLog.capacity)
    #expect(recent.last?.message == "buffer-probe-\(total - 1)")
    #expect(recent.first?.message == "buffer-probe-1")
  }

  /// Every entry answers where it stands. Without the numbers, a screen
  /// showing the lines could not say which came first.
  @Test
  func entriesCarryAnIncreasingSequence() {
    let store = DiagnosticLogStore()
    store.append("buffer-sequence-a")
    store.append("buffer-sequence-b")
    let recent = store.recent
    #expect(recent[0].message == "buffer-sequence-a")
    #expect(recent[1].message == "buffer-sequence-b")
    #expect(recent[0].sequence < recent[1].sequence)
  }

  /// The launch summary is pinned outside the ring: a long run must not
  /// push the startup outcome and the permission state off the screen.
  @Test
  func theLaunchSummarySurvivesEviction() {
    let store = DiagnosticLogStore()
    store.pin("buffer-summary-probe")
    for index in 0 ..< (DiagnosticLog.capacity + 10) {
      store.append("buffer-flood-\(index)")
    }
    #expect(store.summary == "buffer-summary-probe")
    #expect(store.recent.count == DiagnosticLog.capacity)
  }
}

/// Structured lines keep their level, grouping, and payload beside
/// the message, while the mirrored message stays byte-identical.
extension DiagnosticsBufferTests {
  @Test
  func structuredLinesKeepLevelCategoryAndPayload() {
    let store = DiagnosticLogStore()
    var logger = Logger(label: "buffer-probe", factory: { _ in DiagnosticLogHandler(store: store) })
    logger.logLevel = .trace
    logger.warning(
      "buffer-structured-probe",
      metadata: ["category": "ax", "app": ["bundle": "com.example"], "attempts": [["result": "failed"]]]
    )
    let recent = store.recent
    #expect(recent.count == 1)
    #expect(recent[0].message == "buffer-structured-probe")
    #expect(recent[0].level == .warning)
    #expect(recent[0].category == "ax")
    let payload = recent[0].payloadJSON ?? ""
    #expect(payload.contains("com.example"))
    #expect(payload.contains("failed"))
  }
}
