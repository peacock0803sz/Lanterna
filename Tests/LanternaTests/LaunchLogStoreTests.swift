import Foundation
@testable import Lanterna
import Testing

// MARK: - LaunchLogStoreTests

/// Saved launches: their shape on disk, reading them back line by line,
/// and how many are kept.
struct LaunchLogStoreTests {

  // MARK: Internal

  @Test
  func theHeaderAndEachLineTakeTheContractShape() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    let (launch, url) = try store.create(for: Self.launch(0), version: "v0.8.2-59-g50d6058")
    let entry = LogFixture.entry(sequence: 7, context: ["ms": .int(1012)], launch: launch)
    try append(LaunchLogCoding.line(for: entry), to: url)
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    #expect(
      lines[0]
        == #"{"format":1,"launch":"2026-09-30 14:02:10.481","utcOffset":"+09:00","version":"v0.8.2-59-g50d6058"}"#
    )
    let object = try #require(JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any])
    #expect(object["seq"] as? Int == 7)
    #expect(object["ts"] as? Int == Int(entry.capturedAt.timeIntervalSince1970 * 1000))
    #expect(object["level"] as? String == "info")
    #expect(object["category"] as? String == "activate")
    #expect(object["source"] as? String == "Probe.swift:7")
    #expect((object["context"] as? [String: Any])?["ms"] as? Int == 1012)
  }

  @Test
  func readingSkipsDamagedLinesOneByOne() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    let (launch, url) = try store.create(for: Self.launch(0), version: "v0")
    for sequence: UInt64 in 1 ... 3 {
      try append(LaunchLogCoding.line(for: LogFixture.entry(sequence: sequence, launch: launch)), to: url)
      if sequence == 2 {
        try append("{not json}\n", to: url)
        try append(#"{"seq":9,"ts":1,"level":"loud","category":"activate","message":"","source":""}"# + "\n", to: url)
      }
    }
    try append(#"{"seq":4,"ts":17907"#, to: url)
    let read = store.read(try #require(store.files().first))
    #expect(read.isReadable)
    #expect(read.entries.map(\.sequence) == [1, 2, 3])
    #expect(read.skippedLines == 3)
    #expect(read.entries[0].context == [:])
  }

  @Test
  func aFileOfAnotherFormatIsSkippedWhole() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    let url = store.fileURL(for: Self.launch(0))
    try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
    try Data(
      (#"{"format":2,"launch":"x"}"# + "\n" + LaunchLogCoding.line(for: LogFixture.entry(sequence: 1))).utf8
    ).write(to: url)
    let read = store.read(try #require(store.files().first))
    #expect(!read.isReadable)
    #expect(read.entries.isEmpty)
  }

  @Test
  func aTakenNameMovesToTheNextSuffix() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    let first = try store.create(for: Self.launch(0), version: "v0")
    let second = try store.create(for: Self.launch(0), version: "v0")
    #expect(first.url.lastPathComponent == "20260930-140210.481.jsonl")
    #expect(second.url.lastPathComponent == "20260930-140210.481-2.jsonl")
    #expect(second.launch.stamp == "2026-09-30 14:02:10.481-2")
  }

  @Test
  func pruningKeepsTheNewestTwentyAndNeverTheCurrentLaunch() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    for index in 0 ..< 25 {
      _ = try store.create(for: Self.launch(index), version: "v0")
    }
    let current = Self.launch(0)
    store.prune(keeping: current)
    let left = store.files().map(\.launch)
    #expect(left.count == LaunchLogStore.launchLimit + 1)
    #expect(left.contains(current))
    #expect(!left.contains(Self.launch(1)))
    #expect(left.contains(Self.launch(24)))
  }

  @Test
  func pruningDeletesTheOldestPastTheSizeLimit() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    let half = Data(repeating: UInt8(ascii: "x"), count: LaunchLogStore.byteLimit / 2 + 1)
    for index in 0 ..< 3 {
      let made = try store.create(for: Self.launch(index), version: "v0")
      try append(String(decoding: half, as: UTF8.self), to: made.url)
    }
    store.prune(keeping: Self.launch(9))
    #expect(store.files().map(\.launch) == [Self.launch(2)])
  }

  @Test
  func deletingAllKeepsOnlyTheNamedLaunch() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    for index in 0 ..< 3 {
      _ = try store.create(for: Self.launch(index), version: "v0")
    }
    store.deleteAll(except: Self.launch(2))
    #expect(store.files().map(\.launch) == [Self.launch(2)])
    store.deleteAll(except: nil)
    #expect(store.files().isEmpty)
  }

  @Test
  func theUsageSaysHowMuchHowManyAndSinceWhen() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    #expect(store.usage().summary(timeZone: Self.tokyo) == "No saved logs yet.")
    for index in 0 ..< 2 {
      _ = try store.create(for: Self.launch(index), version: "v0")
    }
    let usage = store.usage()
    #expect(usage.launchCount == 2)
    #expect(usage.byteCount > 0)
    #expect(usage.summary(timeZone: Self.tokyo) == "0.0 MB across 2 launches · oldest Sep 30")
  }

  @Test
  func eachOriginKeepsItsOwnFolder() {
    let support = URL(fileURLWithPath: "/tmp/support")
    #expect(
      LaunchLogStore.directory(applicationSupport: support, origin: .installed).path
        == "/tmp/support/Lanterna/Logs/installed"
    )
    let home = URL(fileURLWithPath: "/Users/someone")
    let cases: [(String, LogOrigin)] = [
      ("/Applications/Lanterna.app/Contents/MacOS/Lanterna", .installed),
      ("/Users/someone/Applications/Lanterna.app/Contents/MacOS/Lanterna", .installed),
      ("/nix/store/abc-lanterna/Applications/Lanterna.app/Contents/MacOS/Lanterna", .installed),
      ("/Users/someone/src/Lanterna/.build/debug/Lanterna", .development),
      ("/Users/someone/src/Lanterna/build/Lanterna.app/Contents/MacOS/Lanterna", .development),
    ]
    for (path, origin) in cases {
      #expect(LogOrigin.of(executable: URL(fileURLWithPath: path), home: home) == origin, "for \(path)")
    }
  }

  // MARK: Private

  private static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

  /// A launch `index` minutes after the fixture's, so names sort in order.
  private static func launch(_ index: Int) -> LaunchID {
    LaunchID(
      startedAt: LogFixture.launch.startedAt.addingTimeInterval(Double(index) * 60),
      isCurrent: false,
      timeZone: tokyo
    )
  }

  private func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
  }

}

// MARK: - TemporaryFolder

/// A folder of its own per test, removed when the test lets go of it.
final class TemporaryFolder: Sendable {

  // MARK: Lifecycle

  init() throws {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("lanterna-logs-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  // MARK: Internal

  let url: URL

}
