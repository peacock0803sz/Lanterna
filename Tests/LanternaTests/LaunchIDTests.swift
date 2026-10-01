import Foundation
@testable import Lanterna
import Testing

/// A launch reads as its local start time, and its file name reads back
/// into the same launch.
struct LaunchIDTests {

  // MARK: Internal

  @Test
  func theStampAndTheFileNameNameTheSameInstant() {
    let launch = LaunchID(startedAt: Self.instant, isCurrent: true, timeZone: Self.tokyo)
    #expect(launch.stamp == "2026-09-30 14:02:10.481")
    #expect(launch.fileName == "20260930-140210.481.jsonl")
  }

  @Test
  func aFileNameReadsBackIntoItsLaunch() throws {
    let launch = try #require(LaunchID.fromFileName("20260930-140210.481.jsonl", timeZone: Self.tokyo))
    #expect(launch.stamp == "2026-09-30 14:02:10.481")
    #expect(!launch.isCurrent)
    #expect(abs(launch.startedAt.timeIntervalSince(Self.instant)) < 0.001)
  }

  @Test
  func aTakenNameGetsTheNextSuffixAndStillReadsBack() throws {
    let first = LaunchID(startedAt: Self.instant, isCurrent: true, timeZone: Self.tokyo)
    let second = first.nextSuffix(timeZone: Self.tokyo)
    let third = second.nextSuffix(timeZone: Self.tokyo)
    #expect(second.stamp == "2026-09-30 14:02:10.481-2")
    #expect(second.fileName == "20260930-140210.481-2.jsonl")
    #expect(third.fileName == "20260930-140210.481-3.jsonl")
    #expect(second.isCurrent)
    let read = try #require(LaunchID.fromFileName(third.fileName, timeZone: Self.tokyo))
    #expect(read == third)
  }

  @Test(arguments: [
    "20260930-140210.481.json",
    "20260930-140210.48.jsonl",
    "2026093a-140210.481.jsonl",
    "20261330-140210.481.jsonl",
    "20260930-140210.481-1.jsonl",
    "20260930-140210.481-x.jsonl",
    "notes.jsonl",
  ])
  func otherNamesAreNotLaunches(name: String) {
    #expect(LaunchID.fromFileName(name, timeZone: Self.tokyo) == nil)
  }

  @Test
  func timesReadInTheirFixedShapes() {
    let line = Self.instant.addingTimeInterval(9.637)
    #expect(LogTimeText.clock(line, timeZone: Self.tokyo) == "14:02:20.118")
    #expect(LogTimeText.full(line, timeZone: Self.tokyo) == "2026-09-30 14:02:20.118")
    #expect(LogTimeText.iso(line, timeZone: Self.tokyo) == "2026-09-30T14:02:20.118+09:00")
    #expect(LogTimeText.offset(-16200) == "-04:30")
    #expect(LogTimeText.offset(0) == "+00:00")
  }

  @Test
  func launchesAreEqualByStamp() {
    let current = LaunchID(startedAt: Self.instant, isCurrent: true, timeZone: Self.tokyo)
    let readBack = LaunchID(startedAt: Self.instant, isCurrent: false, timeZone: Self.tokyo)
    #expect(current == readBack)
    #expect(current != current.nextSuffix(timeZone: Self.tokyo))
  }

  // MARK: Private

  private static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

  /// 2026-09-30 14:02:10.481 in Tokyo.
  private static let instant = Date(timeIntervalSince1970: 1_790_744_530.481)

}
