@testable import Lanterna
import Testing

/// The background spill queue, pinned without touching the store:
/// order survives, overflow counts, and failures report instead of
/// recursing.
struct LogSpillWriterTests {

  // MARK: Internal

  @Test
  func flushedLinesArriveInOrder() {
    var received = [[DiagnosticRow]]()
    let writer = LogSpillWriter(
      spill: { received.append($0) },
      onFailure: { _ in Issue.record("no failure expected") }
    )
    writer.enqueue(row(sequence: 1))
    writer.enqueue(row(sequence: 2))
    writer.flushForTests()
    #expect(received.flatMap(\.self).map(\.sequence) == [1, 2])
    #expect(writer.snapshot() == LogSpillWriter.Snapshot(buffered: 0, droppedTotal: 0, lastError: nil))
  }

  @Test
  func overflowDropsTheOldestAndCounts() {
    var received = [[DiagnosticRow]]()
    let writer = LogSpillWriter(
      spill: { received.append($0) },
      onFailure: { _ in },
      bufferCapacity: 2
    )
    writer.enqueue(row(sequence: 1))
    writer.enqueue(row(sequence: 2))
    writer.enqueue(row(sequence: 3))
    writer.flushForTests()
    #expect(received.flatMap(\.self).map(\.sequence) == [2, 3])
    #expect(writer.snapshot().droppedTotal == 1)
  }

  @Test
  func failingFlushesCountAndReport() {
    struct Probe: Error { }
    var reports = [String]()
    let writer = LogSpillWriter(
      spill: { _ in throw Probe() },
      onFailure: { reports.append($0) }
    )
    writer.enqueue(row(sequence: 1))
    writer.enqueue(row(sequence: 2))
    writer.flushForTests()
    #expect(writer.snapshot().droppedTotal == 2)
    #expect(writer.snapshot().lastError != nil)
    #expect(reports.count == 1)
    #expect(writer.snapshot().buffered == 0)
  }

  // MARK: Private

  private func row(sequence: UInt64) -> DiagnosticRow {
    DiagnosticRow(
      sequence: sequence,
      recordedAtMilliseconds: Int64(sequence),
      level: "info",
      category: nil,
      message: "spill-probe-\(sequence)",
      launchID: nil,
      buildVersion: nil,
      payloadJSON: nil
    )
  }

}
