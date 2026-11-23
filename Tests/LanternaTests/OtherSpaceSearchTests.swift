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

  /// A window the probe turns up that the window server keeps on no hidden
  /// Space is an unselected tab, a closed window the application keeps, or
  /// a panel it is not showing. It is not listed, and it is not missing.
  @Test
  func aFoundWindowNotKeptElsewhereIsNotListed() {
    let application = FakeApplication(windowCount: 4)
    application.listedIndices = [0, 1]
    application.probedIndices = [2, 3]

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [102]).get()
    #expect(read?.records.map(\.windowID) == [100, 101, 102])
    #expect(read?.missingOtherSpaceWindows == [])
  }

  /// Whether a minimized window keeps its Space is not known, so a found
  /// one stays listed rather than disappearing.
  @Test
  func aFoundMinimizedWindowIsListedEvenIfNotKeptElsewhere() {
    let application = FakeApplication(windowCount: 4)
    application.listedIndices = [0, 1]
    application.probedIndices = [2, 3]
    application.attributeResult = { index, name in
      index == 3 && name == kAXMinimizedAttribute ? (.success, kCFBooleanTrue) : nil
    }

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [102]).get()
    #expect(read?.records.map(\.windowID) == [100, 101, 102, 103])
    #expect(read?.records.last?.isMinimized == true)
  }

  /// The same holds for the windows of a hidden application.
  @Test
  func aHiddenApplicationsFoundWindowsAreListedEvenIfNotKeptElsewhere() {
    let application = FakeApplication(windowCount: 4)
    application.listedIndices = [0, 1]
    application.probedIndices = [2, 3]

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [102], isHidden: true).get()
    #expect(read?.records.map(\.windowID) == [100, 101, 102, 103])
  }

  /// An application left without a single window row looks past the usual
  /// ids, for the windows still missing only, within the same deadline.
  @Test
  func anApplicationWithoutARowLooksBeyondTheUsualIDs() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = []
    application.probedIndices = [0]
    application.widenedIndices = [1]
    application.attributeResult = { index, name in
      index == 0 && name == kAXRoleAttribute ? (.success, kAXScrollAreaRole as CFString) : nil
    }
    let startedAt = application.clock

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [100, 101, 150]).get()
    #expect(application.probes.map(\.ids) == [WindowProbe.elementIDs, WindowProbe.widenedElementIDs])
    #expect(application.probes.last?.targets == [101, 150])
    #expect(application.probes.last?.deadline == startedAt + ReadBudget.limit)
    #expect(read?.records.map(\.windowID) == [101])
    #expect(read?.missingOtherSpaceWindows == [150])
    #expect(read?.otherSpacesCutShort == false)
  }

  /// A row from the list keeps the look to the usual ids: an application
  /// with a window in view may also keep a helper window on a hidden Space,
  /// and widening for that would search to the end on every pass.
  @Test
  func aListedRowKeepsTheLookToTheUsualIDs() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = [0]
    application.widenedIndices = [1]

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [101]).get()
    #expect(application.probes.map(\.ids) == [WindowProbe.elementIDs])
    #expect(read?.records.map(\.windowID) == [100])
    #expect(read?.missingOtherSpaceWindows == [101])
  }

  /// So does a row the usual ids turned up.
  @Test
  func aProbedRowKeepsTheLookToTheUsualIDs() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = []
    application.probedIndices = [0]
    application.widenedIndices = [1]

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [100, 101]).get()
    #expect(application.probes.map(\.ids) == [WindowProbe.elementIDs])
    #expect(read?.records.map(\.windowID) == [100])
    #expect(read?.missingOtherSpaceWindows == [101])
  }

  /// A read already out of time does not look further, and says it was cut.
  @Test
  func aReadOutOfTimeDoesNotLookBeyondTheUsualIDs() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = []
    application.widenedIndices = [1]
    application.probeCost = ReadBudget.limit

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [101]).get()
    #expect(application.probes.map(\.ids) == [WindowProbe.elementIDs])
    #expect(read?.otherSpacesCutShort == true)
    #expect(read?.missingOtherSpaceWindows == [101])
  }

  /// The widened ids end before the deadline does, so a look that went
  /// through them all and found nothing was not cut short: the window is
  /// missing, and the summary line says so in its own words.
  @Test
  func aLookBeyondThatFindsNothingInTimeIsNotCutShort() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = []

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [101]).get()
    #expect(application.probes.count == 2)
    #expect(read?.otherSpacesCutShort == false)
    #expect(read?.missingOtherSpaceWindows == [101])
  }

  @Test
  func aLookBeyondThatRunsOutOfTimeIsCutShort() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = []
    application.widenedProbeCost = ReadBudget.limit

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [101]).get()
    #expect(application.probes.count == 2)
    #expect(read?.otherSpacesCutShort == true)
    #expect(read?.missingOtherSpaceWindows == [101])
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
