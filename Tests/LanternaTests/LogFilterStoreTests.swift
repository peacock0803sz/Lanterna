import Foundation
@testable import Lanterna
import Testing

// MARK: - LogFilterStoreTests

/// Translated lightweight filters run against a real store, so a
/// predicate the database cannot bind fails here rather than
/// passing as text that only looks right.
struct LogFilterStoreTests {

  // MARK: Internal

  @Test(arguments: [
    ("level>=warn", [1, 2]),
    ("category=ax", [1, 4]),
    ("category!=ax", [2, 3]),
    ("app.bundle=com.example", [1]),
    ("app.bundle!=com.example", [2, 3, 4]),
    ("app.bundle:example", [1]),
    ("attempts[].result=failed", [1]),
    ("attempts[].result!=failed", [2, 3, 4]),
    ("attempts[].result:fail", [1]),
    ("O'Brien", [1]),
    ("message=\"panel shown\"", [2]),
  ])
  func filtersMatchTheStoredRows(filter: String, expected: [UInt64]) throws {
    let result = try run(filter)
    #expect(result.skipped.isEmpty, "\(filter): \(result.skipped.map(\.reason))")
    #expect(result.rows.map(\.sequence) == expected, "\(filter)")
  }

  @Test(arguments: ["a'b=1", "a.b)--=1", "a..b=1", ".a=1"])
  func invalidPayloadPathsSearchTheMessage(filter: String) throws {
    let parsed = LightweightFilter.parse(filter)
    #expect(parsed.conditions.map(\.fragment) == ["instr(message, ?) > 0"])
    #expect(parsed.values == [.text(filter)])
    let result = try run(filter)
    #expect(result.skipped.isEmpty)
    #expect(result.rows.isEmpty)
  }

  // MARK: Private

  private func run(_ filter: String) throws -> ExecutedLogQuery {
    let store = try LogStoreFixture()
    defer { store.remove() }
    try store.insert([
      row(
        1,
        level: "warning",
        category: "ax",
        message: "O'Brien left",
        payload: "{\"app\":{\"bundle\":\"com.example\"},\"attempts\":[{\"result\":\"failed\"},{\"result\":\"ok\"}]}"
      ),
      row(
        2,
        level: "error",
        category: "panel",
        message: "panel shown",
        payload: "{\"app\":{\"bundle\":\"com.other\"},\"attempts\":[{\"result\":\"ok\"}]}"
      ),
      row(3, level: "info", category: nil, message: "plain", payload: nil),
      row(4, level: "debug", category: "ax", message: "debug ax", payload: "{\"attempts\":[]}"),
    ])
    let parsed = LightweightFilter.parse(filter)
    return try LogQueryExecutor(files: [store.url], liveStore: { _ in nil }).run(
      predicate: parsed.predicate,
      values: parsed.values
    )
  }

  private func row(
    _ sequence: UInt64,
    level: String,
    category: String?,
    message: String,
    payload: String?
  ) -> DiagnosticRow {
    DiagnosticRow(
      sequence: sequence,
      recordedAtMilliseconds: Int64(sequence) * 1000,
      level: level,
      category: category,
      message: message,
      launchID: LogStoreFixture.launchID,
      buildVersion: LogStoreFixture.buildVersion,
      payloadJSON: payload
    )
  }

}
