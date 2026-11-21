import ApplicationServices
@testable import Lanterna
import Testing

/// The look for an application's windows on other Spaces: what it is sent
/// for, and what it reports as not found. Window `n` of a fake application
/// has window id `100 + n`.
struct OtherSpaceSearchTests {

  /// Nothing kept elsewhere means nothing to look for, so the application
  /// costs no probe.
  @Test
  func anApplicationWithNothingElsewhereIsNotProbed() {
    let application = FakeApplication(windowCount: 2)

    let read = try? application.read(includesOtherSpaces: true).get()
    #expect(application.probes.isEmpty)
    #expect(read?.missingOtherSpaceWindows == [])
  }

  /// Windows elsewhere that the list already holds are not looked for again.
  @Test
  func windowsTheListHoldsAreNotProbedFor() {
    let application = FakeApplication(windowCount: 2)

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [100, 101]).get()
    #expect(application.probes.isEmpty)
    #expect(read?.missingOtherSpaceWindows == [])
  }

  /// A window the probe never turned up is reported, so the summary line
  /// can say which application lost what.
  @Test
  func windowsTheProbeDidNotFindAreMissing() {
    let application = FakeApplication(windowCount: 3)
    application.listedIndices = [0, 1]
    application.probedIndices = [2]

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [102, 150]).get()
    #expect(read?.records.map(\.windowID) == [100, 101, 102])
    #expect(read?.missingOtherSpaceWindows == [150])
  }

  /// A window the probe found and the rule table excluded was judged, so
  /// it is not missing: there was nothing to list.
  @Test
  func aFoundWindowTheRulesExcludeIsNotMissing() {
    let application = FakeApplication(windowCount: 3)
    application.listedIndices = [0, 1]
    application.probedIndices = [2]
    application.attributeResult = { index, name in
      index == 2 && name == kAXRoleAttribute ? (.success, kAXScrollAreaRole as CFString) : nil
    }

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [102]).get()
    #expect(read?.records.map(\.windowID) == [100, 101])
    #expect(read?.missingOtherSpaceWindows == [])
  }

  /// A window the probe returned but the look ran out of time before
  /// judging is still missing; the ones judged before that stay listed.
  @Test
  func aWindowLeftUnjudgedWhenTimeRanOutIsMissing() {
    let application = FakeApplication(windowCount: 4)
    application.listedIndices = [0, 1]
    application.probedIndices = [2, 3]
    application.costOverride = { index, _ in index == 3 ? .seconds(1) : nil }

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [102, 103]).get()
    #expect(read?.records.map(\.windowID) == [100, 101, 102])
    #expect(read?.otherSpacesCutShort == true)
    #expect(read?.missingOtherSpaceWindows == [103])
  }

  /// With the setting off nothing is looked for and nothing is reported
  /// missing, whatever the window server keeps elsewhere.
  @Test
  func theSettingOffReportsNothingMissing() {
    let application = FakeApplication(windowCount: 2)

    let read = try? application.read(otherSpaceWindows: [150]).get()
    #expect(application.probes.isEmpty)
    #expect(read?.missingOtherSpaceWindows == [])
  }

}
