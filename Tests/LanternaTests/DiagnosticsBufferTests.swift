import Foundation
@testable import Lanterna
import Logging
import Synchronization
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
      store.append(.probe("buffer-probe-\(index)"))
    }
    let recent = store.recent
    #expect(recent.count == DiagnosticLog.capacity)
    #expect(recent.last?.message == "buffer-probe-\(total - 1)")
    #expect(recent.first?.message == "buffer-probe-1")
  }

  /// Numbers start at one and are never reassigned when the oldest lines
  /// leave: a number read off the screen still names the same line.
  @Test
  func sequencesStartAtOneAndSurviveEviction() {
    let store = DiagnosticLogStore()
    store.append(.probe("first"))
    #expect(store.recent.first?.sequence == 1)
    for index in 0 ..< DiagnosticLog.capacity {
      store.append(.probe("flood-\(index)"))
    }
    let recent = store.recent
    #expect(recent.first?.sequence == 2)
    #expect(recent.last?.sequence == UInt64(DiagnosticLog.capacity) + 1)
    #expect(zip(recent, recent.dropFirst()).allSatisfy { $0.sequence + 1 == $1.sequence })
  }

  /// A poll takes only what is newer than what it already has; a reader
  /// that fell behind the ring gets everything still held.
  @Test
  func entriesAfterANumberReturnOnlyTheNewerLines() {
    let store = DiagnosticLogStore()
    for index in 0 ..< 5 {
      store.append(.probe("after-\(index)"))
    }
    #expect(store.entries(after: 0).map(\.sequence) == [1, 2, 3, 4, 5])
    #expect(store.entries(after: 3).map(\.sequence) == [4, 5])
    #expect(store.entries(after: 5).isEmpty)
    #expect(store.entries(after: 9).isEmpty)
    for index in 0 ..< DiagnosticLog.capacity {
      store.append(.probe("flood-\(index)"))
    }
    #expect(store.entries(after: 2).first?.sequence == 6)
    #expect(store.entries(after: 2).count == DiagnosticLog.capacity)
  }

  /// The level, category, source and context ride along into the mirror.
  @Test
  func entriesKeepWhatKindOfLineTheyAre() {
    let store = DiagnosticLogStore()
    store.append(Diagnostics.Record(
      level: .warning,
      category: .activate,
      message: "could not switch",
      source: "PanelExit.swift:376",
      context: ["app": .string("Vivaldi"), "ms": .int(1012), "ok": .bool(false)]
    ))
    let entry = store.recent[0]
    #expect(entry.level == .warning)
    #expect(entry.category == .activate)
    #expect(entry.source == "PanelExit.swift:376")
    #expect(entry.context == ["app": .string("Vivaldi"), "ms": .int(1012), "ok": .bool(false)])
    #expect(entry.launch == store.launch)
  }

  /// stderr gets the message and a newline, nothing else, so grep-based
  /// checks written against earlier builds keep working.
  @Test
  func stderrReceivesTheMessageOnly() {
    let emitted = Mutex([String]())
    let store = DiagnosticLogStore(emit: { text in emitted.withLock { $0.append(text) } })
    store.write(Diagnostics.Record(
      level: .error,
      category: .config,
      message: "config invalid",
      source: "main.swift:80",
      context: ["path": .string("/tmp/config.json")]
    ))
    #expect(emitted.withLock { $0 } == ["config invalid\n"])
    #expect(store.recent.map(\.message) == ["config invalid"])
  }

  /// The handler reads the category and the typed context back out of the
  /// metadata, names the call site, and folds swift-log's extra levels.
  @Test
  func theHandlerKeepsTheCallSiteAndTypedContext() {
    let store = DiagnosticLogStore(emit: { _ in })
    var logger = Logger(label: "buffer-probe", factory: { _ in DiagnosticLogHandler(store: store) })
    logger.logLevel = .trace
    logger.log(
      level: .notice,
      "handler-probe",
      metadata: [
        DiagnosticLogHandler.categoryKey: .string(LogCategory.panel.rawValue),
        DiagnosticLogHandler.contextKey: .stringConvertible(ContextBox(values: ["ms": .int(42)])),
      ],
      file: "Lanterna/PanelPresenter.swift",
      line: 399
    )
    logger.trace("trace-probe")
    logger.critical("critical-probe")
    let recent = store.recent
    #expect(recent[0].level == .info)
    #expect(recent[0].category == .panel)
    #expect(recent[0].source == "PanelPresenter.swift:399")
    #expect(recent[0].context == ["ms": .int(42)])
    #expect(recent[1].level == .debug)
    #expect(recent[2].level == .error)
  }

  /// The launch summary is pinned outside the ring: a long run must not
  /// push the startup outcome and the permission state off the screen.
  @Test
  func theLaunchSummarySurvivesEviction() {
    let store = DiagnosticLogStore()
    store.pin("buffer-summary-probe")
    for index in 0 ..< (DiagnosticLog.capacity + 10) {
      store.append(.probe("buffer-flood-\(index)"))
    }
    #expect(store.summary == "buffer-summary-probe")
    #expect(store.recent.count == DiagnosticLog.capacity)
  }
}

extension Diagnostics.Record {
  /// A plain info line, for tests that only care about the message.
  static func probe(_ message: String, level: Logger.Level = .info, category: LogCategory = .launch) -> Self {
    Diagnostics.Record(level: level, category: category, message: message, source: "Probe.swift:1", context: [:])
  }
}
