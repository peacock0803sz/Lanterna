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

    for live in [false, true] {
      let database = store.database
      let executor = LogQueryExecutor(files: [store.url], liveStore: { _ in live ? database : nil })
      _ = try? executor.runStatement(smuggled)
      #expect(try store.count() == 2)
    }
  }

  @Test
  func liveStoresReadInsideATransactionTheWriterOutlives() throws {
    let store = try LogStoreFixture()
    defer { store.remove() }
    try store.insert([row(sequence: 1, at: 1000)])
    let database = store.database
    let executor = LogQueryExecutor(files: [store.url], liveStore: { _ in database })
    let result = try executor.run(predicate: "1 = 1", values: [])
    #expect(result.rows.map(\.sequence) == [1])
    #expect(result.skipped.isEmpty)
    try store.insert([row(sequence: 2, at: 2000)])
    #expect(try store.count() == 2)
  }

  @Test
  func trailingLineCommentsKeepTheWrapperIntact() throws {
    let store = try LogStoreFixture()
    defer { store.remove() }
    try store.insert([row(sequence: 1, at: 1000), row(sequence: 2, at: 2000)])
    let verdict = DatabaseStatementCheck.check("SELECT * FROM entries WHERE ts_ms >= 0 -- every line")
    #expect(verdict.allowed)
    let result = try LogQueryExecutor(files: [store.url]).runStatement(verdict.effectiveText)
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
    let executor = LogQueryExecutor(files: [older.url, newer.url])
    #expect(try executor.run(predicate: "1 = 1", values: [], limit: 3).rows.map(\.sequence) == [3, 4, 5])
    let statement = try executor.runStatement("SELECT * FROM entries WHERE ts_ms >= 0 ORDER BY ts_ms DESC LIMIT 2")
    #expect(statement.rows.map(\.sequence) == [4, 5])
  }

  @Test
  func statementsWithoutTheirOwnCapKeepTheNewest() throws {
    let store = try LogStoreFixture()
    defer { store.remove() }
    try store.insert((1...7).map { row(sequence: UInt64($0), at: Int64($0) * 1000) })
    let executor = LogQueryExecutor(files: [store.url])
    let verdict = DatabaseStatementCheck.check("SELECT * FROM entries WHERE ts_ms >= 0")
    #expect(try executor.runStatement(verdict.effectiveText, defaultCap: 3).rows.map(\.sequence) == [5, 6, 7])
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
    let result = try LogQueryExecutor(files: [store.url]).runStatement(verdict.effectiveText)
    #expect(result.rows.map(\.sequence) == [6, 7])
  }

  @Test
  func refusedStatementsFailTheRunInsteadOfSkippingEveryFile() throws {
    let first = try LogStoreFixture()
    defer { first.remove() }
    let second = try LogStoreFixture()
    defer { second.remove() }
    let executor = LogQueryExecutor(files: [first.url, second.url])
    #expect(throws: LogQueryExecutor.StatementError.self) {
      try executor.runStatement("SELECT no_such_column FROM entries WHERE ts_ms >= 0")
    }
    #expect(throws: LogQueryExecutor.StatementError.self) {
      try executor.run(predicate: "no_such_column = 1", values: [])
    }
    let missing = first.base.appendingPathComponent("missing.duckdb")
    let result = try LogQueryExecutor(files: [missing, first.url]).run(predicate: "1 = 1", values: [])
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
    let result = try LogQueryExecutor(files: [store.url]).run(predicate: "1 = 1", values: [])
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
