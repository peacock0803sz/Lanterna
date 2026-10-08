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
    #expect(store.usage().summary(timeZone: Self.tokyo) == "No saved logs yet")
    for index in 0 ..< 2 {
      _ = try store.create(for: Self.launch(index), version: "v0")
    }
    let usage = store.usage()
    #expect(usage.launchCount == 2)
    #expect(usage.byteCount > 0)
    #expect(usage.summary(timeZone: Self.tokyo) == "0.0 MB across 2 launches · oldest Sep 30")
  }

  @Test
  func stopsBeforeTheFileThatWouldPassTheBudget() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    let older = try Self.write(count: 8, launch: Self.launch(0), store: store)
    let newer = try Self.write(count: 6, launch: Self.launch(1), store: store)
    let sizes = Dictionary(uniqueKeysWithValues: store.files().map { ($0.launch, $0.byteCount) })
    let olderSize = try #require(sizes[older])
    let newerSize = try #require(sizes[newer])
    let budget = newerSize + olderSize / 2
    let source = SavedLogSource.live(store: store, limits: SavedLogReadLimits(launchCount: 5, byteBudget: budget))
    let batch = source.readOthers(nil)
    #expect(batch.launches.count == 1)
    #expect(batch.launches.first?.launch == newer)
    #expect(batch.bytesRead == newerSize)
    #expect(batch.unreadableFiles == 0)
  }

  @Test
  func aSecondFileAloneOverTheBudgetIsNotRead() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    let older = try Self.write(count: 30, launch: Self.launch(0), store: store)
    let newer = try Self.write(count: 2, launch: Self.launch(1), store: store)
    let sizes = Dictionary(uniqueKeysWithValues: store.files().map { ($0.launch, $0.byteCount) })
    let newerSize = try #require(sizes[newer])
    let olderSize = try #require(sizes[older])
    let budget = newerSize * 5
    #expect(olderSize > budget)
    let source = SavedLogSource.live(store: store, limits: SavedLogReadLimits(launchCount: 5, byteBudget: budget))
    let batch = source.readOthers(nil)
    #expect(batch.launches.count == 1)
    #expect(batch.launches.first?.launch == newer)
    #expect(batch.unreadableFiles == 0)
  }

  @Test
  func aNewestFileAloneOverTheBudgetReadsOnlyItsTail() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    let launch = try Self.write(count: 40, launch: Self.launch(0), store: store)
    let size = try #require(store.files().first { $0.launch == launch }?.byteCount)
    let budget = size / 4
    #expect(size > budget)
    let source = SavedLogSource.live(store: store, limits: SavedLogReadLimits(launchCount: 5, byteBudget: budget))
    let batch = source.readOthers(nil)
    #expect(batch.launches.count == 1)
    #expect(batch.bytesRead <= budget)
    #expect(batch.skippedLines == 0)
    let sequences = batch.launches.first?.entries.map(\.sequence) ?? []
    #expect(sequences.last == 40)
    #expect(sequences == sequences.sorted())
  }

  @Test
  func theTailSkipsItsFragmentWithoutCountingIt() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    let (launch, url) = try store.create(for: Self.launch(0), version: "v0")
    for sequence: UInt64 in 1 ... 30 {
      try append(LaunchLogCoding.line(for: LogFixture.entry(sequence: sequence, launch: launch)), to: url)
      if sequence == 25 {
        try append("{not json}\n", to: url)
      }
    }
    let size = try #require(store.files().first { $0.launch == launch }?.byteCount)
    let budget = size / 3
    let source = SavedLogSource.live(store: store, limits: SavedLogReadLimits(launchCount: 5, byteBudget: budget))
    let batch = source.readOthers(nil)
    #expect(batch.launches.count == 1)
    #expect(batch.bytesRead <= budget)
    #expect(batch.skippedLines == 1)
    #expect(batch.launches.first?.entries.map(\.sequence).last == 30)
  }

  @Test
  func beyondTheLaunchCountOnlyTheNewestAreRead() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    let current = try Self.write(count: 1, launch: Self.launch(9), store: store)
    var launches = [LaunchID]()
    for index in 0 ..< 3 {
      launches.append(try Self.write(count: 2, launch: Self.launch(index), store: store))
    }
    let currentURL = store.fileURL(for: current)
    let source = SavedLogSource.live(store: store, limits: SavedLogReadLimits(launchCount: 2, byteBudget: 10 * 1024 * 1024))
    let batch = source.readOthers(currentURL)
    #expect(batch.launches.map(\.launch) == [Self.launch(1), Self.launch(2)])
    let sizes = Dictionary(uniqueKeysWithValues: store.files().map { ($0.launch, $0.byteCount) })
    #expect(batch.bytesRead == (sizes[Self.launch(1)] ?? 0) + (sizes[Self.launch(2)] ?? 0))
    #expect(batch.unreadableFiles == 0)
  }

  @Test
  func anUnreadableFileStillCountsWhileALimitedOneDoesNot() throws {
    let folder = try TemporaryFolder()
    let store = LaunchLogStore(directory: folder.url, timeZone: Self.tokyo)
    _ = try Self.write(count: 2, launch: Self.launch(1), store: store)
    let brokenURL = store.fileURL(for: Self.launch(0))
    try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
    try Data((#"{"format":2,"launch":"x"}"# + "\n").utf8).write(to: brokenURL)
    let source = SavedLogSource.live(store: store, limits: SavedLogReadLimits(launchCount: 5, byteBudget: 10 * 1024 * 1024))
    let batch = source.readOthers(nil)
    #expect(batch.launches.count == 1)
    #expect(batch.unreadableFiles == 1)
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

  /// Creates one launch's file holding `count` lines, returning it.
  @discardableResult
  private static func write(count: Int, launch: LaunchID, store: LaunchLogStore) throws -> LaunchID {
    let (made, url) = try store.create(for: launch, version: "v0")
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    for sequence: UInt64 in 1 ... UInt64(count) {
      try handle.write(contentsOf: Data(LaunchLogCoding.line(for: LogFixture.entry(sequence: sequence, launch: made)).utf8))
    }
    return made
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
