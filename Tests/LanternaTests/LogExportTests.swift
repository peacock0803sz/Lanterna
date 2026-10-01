import Foundation
@testable import Lanterna
import Testing

// MARK: - LogExportTests

/// Pins the copy and file shapes: text stays one line per row,
/// while the payload form keeps nested structure with launch and build.
struct LogExportTests {

  @Test
  func textCopyKeepsOneLinePerRow() {
    let rows = [
      DiagnosticRow(
        sequence: 7,
        recordedAtMilliseconds: 1_700_000_000_123,
        level: "error",
        category: "activate",
        message: "Failed to raise window",
        launchID: "launch-a",
        buildVersion: "build-a",
        payloadJSON: nil
      ),
      DiagnosticRow(
        sequence: 8,
        recordedAtMilliseconds: 1_700_000_001_456,
        level: "info",
        category: nil,
        message: "Panel shown",
        launchID: "launch-a",
        buildVersion: "build-a",
        payloadJSON: nil
      ),
    ]
    let text = LogExport.textLines(rows: rows)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == 2)
    #expect(text.contains("#7"))
    #expect(text.contains("ERROR"))
    #expect(text.contains("activate"))
    #expect(text.contains("Failed to raise window"))
    #expect(text.contains("#8"))
    #expect(text.contains("Panel shown"))
  }

  @Test
  func jsonLinesKeepNestedPayload() throws {
    let row = DiagnosticRow(
      sequence: 5,
      recordedAtMilliseconds: 1_700_000_000_000,
      level: "warning",
      category: "ax",
      message: "Timed out",
      launchID: "launch-a",
      buildVersion: "build-a",
      payloadJSON: "{\"app\":{\"bundle\":\"com.example\",\"pid\":8123},\"attempts\":[{\"result\":\"failed\"}]}"
    )
    let lines = LogExport.jsonLines(rows: [row])
    #expect(!lines.contains("\n"))
    let data = try #require(lines.data(using: .utf8))
    let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(decoded["seq"] as? Int == 5)
    #expect(decoded["level"] as? String == "warning")
    let payload = try #require(decoded["payload"] as? [String: Any])
    let app = try #require(payload["app"] as? [String: Any])
    #expect(app["bundle"] as? String == "com.example")
    let attempts = try #require(payload["attempts"] as? [[String: Any]])
    #expect(attempts.first?["result"] as? String == "failed")
  }

  @Test
  func fileAndJsonCarryLaunchAndBuild() throws {
    let row = DiagnosticRow(
      sequence: 3,
      recordedAtMilliseconds: 1_700_000_000_000,
      level: "info",
      category: "panel",
      message: "Shown",
      launchID: "launch-past",
      buildVersion: "build-past",
      payloadJSON: "{\"window\":{\"title\":\"Example\"}}"
    )
    for body in [LogExport.jsonLines(rows: [row]), LogExport.fileContents(rows: [row])] {
      let data = try #require(body.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8))
      let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
      #expect(decoded["launch_id"] as? String == "launch-past")
      #expect(decoded["build_version"] as? String == "build-past")
      let payload = try #require(decoded["payload"] as? [String: Any])
      let window = try #require(payload["window"] as? [String: Any])
      #expect(window["title"] as? String == "Example")
    }
    #expect(LogExport.fileContents(rows: []).isEmpty)
  }

}
