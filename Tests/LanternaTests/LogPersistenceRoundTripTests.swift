import DuckDB
import Foundation
@testable import Lanterna
import Testing

/// A real temp-directory round trip: open a store, insert rows,
/// and read them back ordered through the executor. A garbage
/// file beside the store is skipped with its reason kept.
struct LogPersistenceRoundTripTests {
  @Test
  func storedRowsReturnOrderedAndGarbageSkipped() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let launchID = "round-trip-launch"
    let buildVersion = "test-build"
    let storeURL = LogPersistence.fileURL(in: base, launchID: launchID)
    let database = try LogPersistence.openStore(
      at: storeURL,
      launchID: launchID,
      origin: .development,
      buildVersion: buildVersion,
      startedAtMilliseconds: 1_700_000_000_000
    )
    let rows = [
      DiagnosticRow(
        sequence: 2,
        recordedAtMilliseconds: 2000,
        level: "info",
        category: nil,
        message: "second",
        launchID: launchID,
        buildVersion: buildVersion,
        payloadJSON: nil
      ),
      DiagnosticRow(
        sequence: 1,
        recordedAtMilliseconds: 1000,
        level: "debug",
        category: "panel",
        message: "first",
        launchID: launchID,
        buildVersion: buildVersion,
        payloadJSON: "{\"key\":\"value\"}"
      ),
      DiagnosticRow(
        sequence: 3,
        recordedAtMilliseconds: 3000,
        level: "error",
        category: nil,
        message: "third",
        launchID: launchID,
        buildVersion: buildVersion,
        payloadJSON: nil
      ),
    ]
    let connection = try database.connect()
    try connection.execute(
      LogPersistence.insertStatement(rows: rows, launchID: launchID, buildVersion: buildVersion)
    )
    let garbageURL = base.appendingPathComponent("garbage.duckdb")
    try "not a database".write(to: garbageURL, atomically: true, encoding: .utf8)
    let executor = LogQueryExecutor(files: [storeURL, garbageURL], liveStore: { _ in nil })
    let result = try executor.run(predicate: "1 = 1", values: [])
    #expect(result.rows.map(\.sequence) == [1, 2, 3])
    #expect(result.rows.first?.message == "first")
    #expect(result.skipped.count == 1)
    #expect(result.skipped.first?.url == garbageURL)
    #expect(!(result.skipped.first?.reason.isEmpty ?? true))
  }

  @Test(arguments: [
    ["CREATE TABLE meta(key VARCHAR, value VARCHAR)", "INSERT INTO meta VALUES ('format_version', '0')"],
    ["CREATE TABLE notes(body VARCHAR)"],
  ])
  func otherShapesAreRefusedAndLeftAsFound(setup: [String]) throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let url = base.appendingPathComponent("other.duckdb")
    do {
      let connection = try Database(store: .file(at: url)).connect()
      for statement in setup {
        try connection.execute(statement)
      }
    }
    #expect(throws: LogPersistence.OpenError.self) {
      try LogPersistence.openStore(
        at: url,
        launchID: "other",
        origin: .development,
        buildVersion: "test-build",
        startedAtMilliseconds: 0
      )
    }
    let tables = try Database(store: .file(at: url)).connect()
      .query("SELECT table_name FROM information_schema.tables")
    #expect(tables.rowCount == 1)
  }

  @Test
  func freshStoresInMemoryOpenWithTheirTables() throws {
    let database = try LogPersistence.openEphemeral(
      launchID: "ephemeral",
      origin: .development,
      buildVersion: "test-build",
      startedAtMilliseconds: 0
    )
    let tables = try database.connect().query("SELECT table_name FROM information_schema.tables")
    #expect(tables.rowCount == LogPersistence.schemaStatements.count)
  }
}
