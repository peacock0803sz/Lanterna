import DuckDB
import Foundation
@testable import Lanterna
import Testing

// MARK: - LogQueryExecutorTests

/// Reads against real store files in a temp directory: the read
/// path never writes, whether the file is held open by this launch
/// or opened fresh.
struct LogQueryExecutorTests {

  // MARK: Internal

  @Test
  func smuggledStatementsLeaveTheStoreIntact() throws {
    let store = try LogStoreFixture()
    defer { store.remove() }
    try store.insert([row(sequence: 1, at: 1000), row(sequence: 2, at: 2000)])
    let wrapped = "COPY (SELECT seq, ts_ms, level, category, message, launch_id, build_version, payload "
      + "FROM (\n\(smuggled)\n) ORDER BY ts_ms, seq) TO \(LogPersistence.literal(store.scratch.path)) (HEADER false)"

    // Positive control: the same text run unprepared does delete.
    let control = try LogStoreFixture()
    defer { control.remove() }
    try control.insert([row(sequence: 1, at: 1000)])
    try control.database.connect().execute(wrapped)
    #expect(try control.count() == 0)

    // Live: the count reads through the same instance the read used.
    let database = store.database
    _ = try? LogQueryExecutor(files: [store.url], liveStore: { _ in database }).runStatement(smuggled)
    #expect(try store.count() == 2)

    // Not live: no other instance is open while the reader runs, and
    // the count opens the file afresh after the reader is gone, so a
    // write through the reader's own instance would show.
    let closed = try LogStoreFixture.closedStore(rows: [row(sequence: 1, at: 1000), row(sequence: 2, at: 2000)])
    defer { try? FileManager.default.removeItem(at: closed.deletingLastPathComponent()) }
    _ = try? LogQueryExecutor(files: [closed], liveStore: { _ in nil }).runStatement(smuggled)
    #expect(try LogStoreFixture.count(at: closed) == 2)
  }

  @Test
  func liveStoresReadInsideATransactionTheWriterOutlives() throws {
    // The file holds one row and the live store another, so the
    // answer shows which of the two the read went through.
    let store = try LogStoreFixture()
    defer { store.remove() }
    try store.insert([row(sequence: 1, at: 1000)])
    let live = try LogPersistence.openEphemeral(
      launchID: LogStoreFixture.launchID,
      origin: .development,
      buildVersion: LogStoreFixture.buildVersion,
      startedAtMilliseconds: 0
    )
    try live.connect().execute(
      LogPersistence.insertStatement(
        rows: [row(sequence: 9, at: 9000)],
        launchID: LogStoreFixture.launchID,
        buildVersion: LogStoreFixture.buildVersion
      )
    )
    let storeURL = store.url
    let executor = LogQueryExecutor(files: [store.url], liveStore: { $0 == storeURL ? live : nil })
    let result = try executor.run(predicate: "1 = 1", values: [])
    #expect(result.rows.map(\.sequence) == [9])
    #expect(result.skipped.isEmpty)
    try live.connect().execute(
      LogPersistence.insertStatement(
        rows: [row(sequence: 10, at: 10000)],
        launchID: LogStoreFixture.launchID,
        buildVersion: LogStoreFixture.buildVersion
      )
    )
  }

  @Test
  func trailingLineCommentsKeepTheWrapperIntact() throws {
    let store = try LogStoreFixture()
    defer { store.remove() }
    try store.insert([row(sequence: 1, at: 1000), row(sequence: 2, at: 2000)])
    let verdict = DatabaseStatementCheck.check("SELECT * FROM entries WHERE ts_ms >= 0 -- every line")
    #expect(verdict.allowed)
    let result = try LogQueryExecutor(files: [store.url], liveStore: { _ in nil }).runStatement(verdict.effectiveText)
    #expect(result.skipped.isEmpty)
    #expect(result.rows.map(\.sequence) == [1, 2])
  }

  @Test
  func theRowCapKeepsTheNewestAcrossFiles() throws {
    let older = try LogStoreFixture()
    defer { older.remove() }
    let newer = try LogStoreFixture()
    defer { newer.remove() }
    try older.insert([row(sequence: 1, at: 1000), row(sequence: 2, at: 2000), row(sequence: 3, at: 3000)])
    try newer.insert([row(sequence: 4, at: 4000), row(sequence: 5, at: 5000)])
    let executor = LogQueryExecutor(files: [older.url, newer.url], liveStore: { _ in nil })
    #expect(try executor.run(predicate: "1 = 1", values: [], limit: 3).rows.map(\.sequence) == [3, 4, 5])
    let statement = try executor.runStatement("SELECT * FROM entries WHERE ts_ms >= 0 ORDER BY ts_ms DESC LIMIT 2")
    #expect(statement.rows.map(\.sequence) == [4, 5])
  }

  @Test
  func statementsWithoutTheirOwnCapKeepTheNewest() throws {
    let store = try LogStoreFixture()
    defer { store.remove() }
    try store.insert((1...7).map { row(sequence: UInt64($0), at: Int64($0) * 1000) })
    let executor = LogQueryExecutor(files: [store.url], liveStore: { _ in nil })
    let verdict = DatabaseStatementCheck.check("SELECT * FROM entries WHERE ts_ms >= 0")
    #expect(try executor.runStatement(verdict.effectiveText, defaultCap: 3).rows.map(\.sequence) == [5, 6, 7])
    #expect(try executor.run(predicate: "1 = 1", values: [], limit: 3).rows.map(\.sequence) == [5, 6, 7])
  }

  @Test(arguments: [
    (
      "SELECT * FROM entries WHERE ts_ms > 0 AND launch_id = "
        + "(SELECT launch_id FROM launches ORDER BY started_at DESC LIMIT 1)",
      [UInt64(3), 4, 5, 6, 7]
    ),
    ("SELECT * FROM entries WHERE ts_ms > (SELECT min(ts_ms) FROM entries LIMIT 1)", [3, 4, 5, 6, 7]),
    ("SELECT * FROM entries WHERE ts_ms IN (SELECT ts_ms FROM entries LIMIT 100)", [3, 4, 5, 6, 7]),
    ("SELECT * FROM entries WHERE ts_ms > (SELECT 0 LIMIT 1) ORDER BY ts_ms DESC LIMIT 2", [6, 7]),
  ])
  func onlyATopLevelLimitReplacesTheDefaultCap(statement: String, expected: [UInt64]) throws {
    let store = try LogStoreFixture()
    defer { store.remove() }
    try store.insert((1...7).map { row(sequence: UInt64($0), at: Int64($0) * 1000) })
    let executor = LogQueryExecutor(files: [store.url], liveStore: { _ in nil })
    #expect(try executor.runStatement(statement, defaultCap: 5).rows.map(\.sequence) == expected)
  }

  @Test
  func ownCapsEndingInALineCommentStillRun() throws {
    let store = try LogStoreFixture()
    defer { store.remove() }
    try store.insert((1...7).map { row(sequence: UInt64($0), at: Int64($0) * 1000) })
    let verdict = DatabaseStatementCheck.check(
      "SELECT * FROM entries WHERE ts_ms >= 0 ORDER BY ts_ms DESC LIMIT 2 -- newest pair"
    )
    #expect(verdict.allowed)
    let result = try LogQueryExecutor(files: [store.url], liveStore: { _ in nil }).runStatement(verdict.effectiveText)
    #expect(result.rows.map(\.sequence) == [6, 7])
  }

  @Test
  func refusedStatementsFailTheRunInsteadOfSkippingEveryFile() throws {
    let first = try LogStoreFixture()
    defer { first.remove() }
    let second = try LogStoreFixture()
    defer { second.remove() }
    let executor = LogQueryExecutor(files: [first.url, second.url], liveStore: { _ in nil })
    #expect(throws: LogQueryExecutor.StatementError.self) {
      try executor.runStatement("SELECT no_such_column FROM entries WHERE ts_ms >= 0")
    }
    #expect(throws: LogQueryExecutor.StatementError.self) {
      try executor.run(predicate: "no_such_column = 1", values: [])
    }
    let missing = first.base.appendingPathComponent("missing.duckdb")
    let result = try LogQueryExecutor(files: [missing, first.url], liveStore: { _ in nil }).run(predicate: "1 = 1", values: [])
    #expect(result.skipped.map(\.url) == [missing])
  }

  @Test
  func delimitersAndLineBreaksSurviveTheRoundTrip() throws {
    let store = try LogStoreFixture()
    defer { store.remove() }
    let original = DiagnosticRow(
      sequence: 1,
      recordedAtMilliseconds: 1000,
      level: "info",
      category: "a,b 'c'",
      message: "it's, \"quoted\"\nline two\r\nline three\rend,",
      launchID: LogStoreFixture.launchID,
      buildVersion: LogStoreFixture.buildVersion,
      payloadJSON: "{\"note\":\"O'Brien, \\\"x\\\"\\n\",\"raw\":\"a,b\"}"
    )
    try store.insert([original])
    let result = try LogQueryExecutor(files: [store.url], liveStore: { _ in nil }).run(predicate: "1 = 1", values: [])
    #expect(result.skippedLines == 0)
    #expect(result.rows == [original])
  }

  // MARK: Private

  private let smuggled = "SELECT * FROM entries) ORDER BY ts_ms, seq) TO '/dev/null' (HEADER false); "
    + "DELETE FROM entries; COPY (SELECT * FROM (SELECT * FROM entries"

  private func row(sequence: UInt64, at milliseconds: Int64, message: String? = nil) -> DiagnosticRow {
    DiagnosticRow(
      sequence: sequence,
      recordedAtMilliseconds: milliseconds,
      level: "info",
      category: nil,
      message: message ?? "line-\(sequence)",
      launchID: LogStoreFixture.launchID,
      buildVersion: LogStoreFixture.buildVersion,
      payloadJSON: nil
    )
  }

}

// MARK: - LogStoreFixture

/// One writable store file in its own temp directory.
struct LogStoreFixture {

  // MARK: Lifecycle

  init(name: String = "fixture") throws {
    base = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    url = LogPersistence.fileURL(in: base, launchID: name)
    database = try LogPersistence.openStore(
      at: url,
      launchID: Self.launchID,
      origin: .development,
      buildVersion: Self.buildVersion,
      startedAtMilliseconds: 0
    )
  }

  // MARK: Internal

  static let launchID = "fixture-launch"
  static let buildVersion = "fixture-build"

  let base: URL
  let url: URL
  let database: Database

  /// A path inside the fixture directory for exports.
  var scratch: URL {
    base.appendingPathComponent("scratch.csv")
  }

  /// A store file holding `rows` with no instance left open on it,
  /// in a temp directory of its own.
  static func closedStore(rows: [DiagnosticRow]) throws -> URL {
    let fixture = try LogStoreFixture()
    try fixture.insert(rows)
    return fixture.url
  }

  /// Counts entries through an instance opened just for the count.
  static func count(at url: URL) throws -> Int {
    let result = try Database(store: .file(at: url)).connect().query("SELECT count(*)::VARCHAR FROM entries")
    return Int(result[0].cast(to: String.self)[0] ?? "") ?? -1
  }

  func insert(_ rows: [DiagnosticRow]) throws {
    try database.connect().execute(
      LogPersistence.insertStatement(rows: rows, launchID: Self.launchID, buildVersion: Self.buildVersion)
    )
  }

  func count() throws -> Int {
    let result = try database.connect().query("SELECT count(*)::VARCHAR FROM entries")
    return Int(result[0].cast(to: String.self)[0] ?? "") ?? -1
  }

  func remove() {
    try? FileManager.default.removeItem(at: base)
  }

}
