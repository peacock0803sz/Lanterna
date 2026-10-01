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
