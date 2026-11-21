import AppKit
@testable import Lanterna
import Testing

/// How a pass hands each application what the window server keeps of it on
/// hidden Spaces, and whether it is hidden.
@MainActor
struct WindowEnumeratorOtherSpaceTests {

  /// With the setting on, the window server is asked once per pass, and
  /// each application is handed its own windows from the answer.
  @Test
  func eachApplicationIsHandedItsOwnWindowsElsewhere() {
    let reader = FakeReader([:])
    var locator = FakeSpaceLocator()
    locator.otherSpace = OtherSpaceWindows(windows: [1: [10, 11], 2: [20]])

    _ = WindowEnumerator(reader: reader, locator: locator, readsOtherSpaces: true)
      .enumerate(applications: [application(1), application(2, name: "Safari"), application(3, name: "Mail")], startedAt: .now)

    #expect(locator.calls.otherSpaceReads == 1)
    #expect(reader.calls.byProcess[1]?.otherSpaceWindows == [10, 11])
    #expect(reader.calls.byProcess[2]?.otherSpaceWindows == [20])
    #expect(reader.calls.byProcess[3]?.otherSpaceWindows == [])
  }

  /// With the setting off the window server is not asked, and no
  /// application is handed anything to look for.
  @Test
  func theSettingOffNeverAsksForWindowsElsewhere() {
    let reader = FakeReader([:])
    var locator = FakeSpaceLocator()
    locator.otherSpace = OtherSpaceWindows(windows: [1: [10]])

    _ = WindowEnumerator(reader: reader, locator: locator)
      .enumerate(applications: [application(1)], startedAt: .now)

    #expect(locator.calls.otherSpaceReads == 0)
    #expect(reader.calls.byProcess[1]?.otherSpaceWindows == [])
  }

  /// Whether an application is hidden is read with its name, on the main
  /// thread, and handed to its read.
  @Test
  func eachApplicationIsToldWhetherItIsHidden() {
    let reader = FakeReader([:])

    _ = WindowEnumerator(reader: reader, locator: FakeSpaceLocator(), readsOtherSpaces: true)
      .enumerate(applications: [application(1, isHidden: true), application(2, name: "Safari")], startedAt: .now)

    #expect(reader.calls.byProcess[1]?.isHidden == true)
    #expect(reader.calls.byProcess[2]?.isHidden == false)
  }

  /// The off-main-thread path hands over the same arguments.
  @Test
  func theOffMainThreadPassHandsOverTheSame() async {
    let reader = FakeReader([:])
    var locator = FakeSpaceLocator()
    locator.otherSpace = OtherSpaceWindows(windows: [1: [10]])

    _ = await WindowEnumerator(reader: reader, locator: locator, readsOtherSpaces: true)
      .enumerateOffMainThread(applications: [application(1, isHidden: true)], startedAt: .now)

    #expect(reader.calls.byProcess[1] == ReadCalls.Call(otherSpaceWindows: [10], isHidden: true))
  }

}
