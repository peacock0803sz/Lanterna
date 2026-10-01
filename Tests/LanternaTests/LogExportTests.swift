import Foundation
@testable import Lanterna
import Testing

/// The copied text and the exported lines, pinned against the contract's
/// examples.
struct LogExportTests {

  // MARK: Internal

  @Test
  func aCopiedLineReadsLaunchNumberTimeLevelCategoryAndMessage() {
    #expect(
      LogExport.copyLine(Self.switchLine, timeZone: Self.tokyo)
        == "2026-09-30 14:02:10.481 #7 14:02:20.118 INFO activate "
        + "could not switch to Vivaldi — Lanterna (timed out) 1012 ms"
    )
  }

  @Test
  func lineBreaksInACopiedMessageBecomeOneLine() {
    let entry = LogFixture.entry(sequence: 2, level: .warning, category: .config, message: "first\nsecond")
    let text = LogExport.copyText([entry, entry], timeZone: Self.tokyo)
    #expect(text.split(separator: "\n").count == 2)
    #expect(text.hasSuffix("WARN config first⏎second"))
  }

  @Test
  func anExportedLineKeepsTheFieldOrder() {
    #expect(
      LogExport.jsonLine(Self.switchLine, timeZone: Self.tokyo)
        == #"{"launch":"2026-09-30 14:02:10.481","seq":7,"time":"2026-09-30T14:02:20.118+09:00","#
        + #""level":"info","category":"activate","#
        + #""message":"could not switch to Vivaldi — Lanterna (timed out) 1012 ms","#
        + #""source":"Probe.swift:7","#
        + #""context":{"app":"Vivaldi","bundle":"com.vivaldi.Vivaldi","ms":1012,"pid":8123,"result":"timedOut"}}"#
    )
  }

  @Test
  func anExportedLineWithoutContextWritesAnEmptyObject() throws {
    let line = LogExport.jsonLine(LogFixture.entry(sequence: 1, message: "say \"hi\"\n"), timeZone: Self.tokyo)
    #expect(line.hasSuffix(#""context":{}}"#))
    let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    #expect(object["message"] as? String == "say \"hi\"\n")
  }

  @Test
  func anExportEndsEveryLineWithANewline() {
    let text = LogExport.jsonLines(LogFixture.entries(count: 3), timeZone: Self.tokyo)
    #expect(text.hasSuffix("}\n"))
    #expect(text.split(separator: "\n").count == 3)
  }

  @Test
  func theDefaultFileNameCarriesTheLocalTime() {
    let date = Date(timeIntervalSince1970: 1_790_853_303)
    #expect(LogExport.defaultFileName(at: date, timeZone: Self.tokyo) == "Lanterna Logs 2026-10-01 20-15-03.jsonl")
  }

  // MARK: Private

  private static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

  private static let switchLine = Diagnostics.LogEntry(
    launch: LogFixture.launch,
    sequence: 7,
    capturedAt: Date(timeIntervalSince1970: 1_790_744_540.118),
    level: .info,
    category: .activate,
    message: "could not switch to Vivaldi — Lanterna (timed out) 1012 ms",
    source: "Probe.swift:7",
    context: [
      "app": .string("Vivaldi"),
      "bundle": .string("com.vivaldi.Vivaldi"),
      "pid": .int(8123),
      "result": .string("timedOut"),
      "ms": .int(1012),
    ]
  )

}
