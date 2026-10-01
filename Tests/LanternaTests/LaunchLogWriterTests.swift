import Foundation
@testable import Lanterna
import Synchronization
import Testing

// MARK: - LaunchLogWriterTests

/// Lines reach this launch's file as they are written, and saving can be
/// switched off, on and back again without losing or doubling a line.
struct LaunchLogWriterTests {

  // MARK: Internal

  /// The line is in the file by the time `write` returns: nothing waits
  /// on a queue that a killed process would lose.
  @Test
  func aLineIsInTheFileWhenWriteReturns() throws {
    let made = try Self.made()
    let store = Self.store()
    store.attach(try made.writer())
    store.write(.probe("first"))
    #expect(try made.entries().map(\.message) == ["first"])
    store.write(.probe("second"))
    #expect(try made.entries().map(\.message) == ["first", "second"])
  }

  /// Lines from before the file existed are caught up on when it is
  /// attached, in order and once each.
  @Test
  func attachingCatchesUpOnWhatTheMirrorHeld() throws {
    let made = try Self.made()
    let store = Self.store()
    store.write(.probe("early-1"))
    store.write(.probe("early-2"))
    store.attach(try made.writer())
    store.write(.probe("late"))
    let entries = try made.entries()
    #expect(entries.map(\.message) == ["early-1", "early-2", "late"])
    #expect(entries.map(\.sequence) == [1, 2, 3])
  }

  /// A failed write stops saving for the launch, says so once on stderr
  /// and in the mirror, and never blocks the caller.
  @Test
  func aFailedWriteStopsSavingAndSaysSoOnce() throws {
    let emitted = Mutex([String]())
    let store = DiagnosticLogStore(launch: LogFixture.launch, emit: { text in emitted.withLock { $0.append(text) } })
    let sink = FailingSink()
    let writer = try LaunchLogWriter(
      url: URL(fileURLWithPath: "/tmp/lanterna-failing.jsonl"),
      header: "",
      openSink: { _ in sink }
    )
    store.attach(writer)
    store.write(.probe("kept"))
    sink.fails = true
    store.write(.probe("lost"))
    store.write(.probe("after"))
    #expect(sink.written == ["kept"])
    let warnings = store.recent.filter { $0.category == .logs }
    #expect(warnings.count == 1)
    #expect(warnings.first?.level == .warning)
    #expect(emitted.withLock { $0 }.count { $0.hasPrefix("logs: could not write") } == 1)
    #expect(store.savingTo == nil)
  }

  /// Off stops the file; lines meanwhile never reach it, even once saving
  /// is back on; on again appends to the same file.
  @Test
  func switchingOffAndOnAgainSkipsTheLinesInBetween() throws {
    let made = try Self.made()
    let store = Self.store()
    let writer = try made.writer()
    store.attach(writer)
    store.write(.probe("before"))
    store.detach()
    store.write(.probe("while off"))
    try writer.reopen()
    store.attach(writer)
    store.write(.probe("after"))
    let entries = try made.entries()
    #expect(entries.map(\.message) == ["before", "after"])
    #expect(entries.map(\.sequence) == [1, 3])
  }

  /// A file deleted while saving was off is made again with its header.
  @Test
  func onAgainAfterDeletingStartsAFreshFile() throws {
    let made = try Self.made()
    let store = Self.store()
    let writer = try made.writer()
    store.attach(writer)
    store.write(.probe("before"))
    store.detach()
    try FileManager.default.removeItem(at: made.url)
    try writer.reopen()
    store.attach(writer)
    store.write(.probe("after"))
    let read = made.store.read(try #require(made.store.files().first))
    #expect(read.isReadable)
    #expect(read.entries.map(\.message) == ["after"])
  }

  /// A launch that starts with saving off and turns it on later writes
  /// only from then on, not the lines from its start.
  @Test
  func turningSavingOnLaterSkipsTheLinesFromTheStart() throws {
    let made = try Self.made()
    let store = Self.store()
    store.write(.probe("at launch"))
    store.declineSaving()
    store.write(.probe("still off"))
    store.attach(try made.writer())
    store.write(.probe("on"))
    #expect(try made.entries().map(\.message) == ["on"])
  }

  // MARK: Private

  private struct Made {
    let folder: TemporaryFolder
    let store: LaunchLogStore
    let url: URL
    let header: String

    func writer() throws -> LaunchLogWriter {
      try LaunchLogWriter(url: url, header: header)
    }

    func entries() throws -> [Diagnostics.LogEntry] {
      store.read(try #require(store.files().first)).entries
    }
  }

  private static func made() throws -> Made {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url)
    let created = try store.create(for: LogFixture.launch, version: "v0")
    let header = LaunchLogCoding.header(launch: created.launch, version: "v0", utcOffsetSeconds: 0)
    return Made(folder: folder, store: store, url: created.url, header: header)
  }

  private static func store() -> DiagnosticLogStore {
    DiagnosticLogStore(launch: LogFixture.launch, emit: { _ in })
  }

}

// MARK: - FailingSink

/// A sink that takes lines until told to fail.
// swiftlint:disable:next no_unchecked_sendable - Touched only by the test that owns it, one call at a time
final class FailingSink: LaunchLogSink, @unchecked Sendable {
  var fails = false
  private(set) var written = [String]()

  func write(_ data: Data) throws {
    if fails {
      throw POSIXError(.ENOSPC)
    }
    let line = String(decoding: data, as: UTF8.self)
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let message = object["message"] as? String {
      written.append(message)
    } else {
      written.append(line)
    }
  }

  func close() { }
}
