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

  /// A window the probe did not turn up may still be the application's
  /// main window, which the application names whatever its element id.
  /// The probe is asked once.
  @Test
  func aMissingMainWindowIsReachedThroughTheApplication() {
    let application = FakeApplication(windowCount: 3)
    application.listedIndices = []
    application.probedIndices = [0]
    application.mainWindowIndex = 1
    application.attributeResult = { index, name in
      index == 0 && name == kAXRoleAttribute ? (.success, kAXScrollAreaRole as CFString) : nil
    }

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [100, 101, 150]).get()
    #expect(application.probes.count == 1)
    #expect(read?.records.map(\.windowID) == [101])
    #expect(read?.missingOtherSpaceWindows == [150])
    #expect(read?.otherSpacesCutShort == false)
  }

  @Test
  func aMissingFocusedWindowIsReachedThroughTheApplication() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = []
    application.focusedWindowIndex = 1

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [101]).get()
    #expect(read?.records.map(\.windowID) == [101])
    #expect(read?.missingOtherSpaceWindows == [])
  }

  /// Main and focused are usually the same window, which is judged once.
  @Test
  func aWindowBothMainAndFocusedIsJudgedOnce() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = []
    application.mainWindowIndex = 1
    application.focusedWindowIndex = 1

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [101]).get()
    #expect(read?.records.map(\.windowID) == [101])
    #expect(application.attributesRead(of: 1).count(where: { $0 == kAXRoleAttribute }) == 1)
  }

  /// Only a window still missing is taken from those answers: the
  /// application's word adds nothing the window server does not keep
  /// elsewhere. The application is hidden, whose found windows are listed
  /// wherever they are kept, so only that rule keeps this one out.
  @Test
  func aMainWindowThatIsNotMissingIsNotListed() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = []
    application.mainWindowIndex = 0

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [101], isHidden: true).get()
    #expect(read?.records.isEmpty == true)
    #expect(read?.missingOtherSpaceWindows == [101])
  }

  /// An application with a row is asked too: its main window may be the
  /// one elsewhere.
  @Test
  func anApplicationWithARowIsAskedToo() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = [0]
    application.mainWindowIndex = 1

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [101]).get()
    #expect(read?.records.map(\.windowID) == [100, 101])
    #expect(read?.missingOtherSpaceWindows == [])
  }

  /// Nothing missing after the probe means nothing to ask.
  @Test
  func nothingMissingAfterTheProbeAsksNothing() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = []
    application.probedIndices = [1]
    application.mainWindowIndex = 1

    _ = application.read(includesOtherSpaces: true, otherSpaceWindows: [101])
    #expect(!application.attributesRead.contains(kAXMainWindowAttribute))
    #expect(!application.attributesRead.contains(kAXFocusedWindowAttribute))
  }

  /// An application that answers both its main and its focused window with
  /// an explicit "no value" while the window server keeps one elsewhere is
  /// said to name none: a window it closed but kept was seen to answer just
  /// so, where every application with a real window there named it.
  @Test
  func anApplicationNamingNoWindowIsSaidTo() {
    let application = FakeApplication(windowCount: 1)
    application.listedIndices = []

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [150]).get()
    #expect(read?.namesNoWindow == true)
    #expect(read?.missingOtherSpaceWindows == [150])
  }

  /// Naming any window, even one not missing, is not naming none.
  @Test
  func anApplicationNamingAnotherWindowIsNotSaidToNameNone() {
    let application = FakeApplication(windowCount: 1)
    application.listedIndices = []
    application.mainWindowIndex = 0

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [150]).get()
    #expect(read?.namesNoWindow == false)
  }

  /// Only an explicit "no value" to both counts. An application refusing
  /// the attribute, as a Chromium web app shim does with some, has said
  /// nothing about its windows.
  @Test
  func anApplicationRefusingTheAttributesIsNotSaidToNameNone() {
    let application = FakeApplication(windowCount: 1)
    application.listedIndices = []
    application.attributeResult = { index, name in
      index == nil && name != kAXWindowsAttribute ? (.failure, nil) : nil
    }

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [150]).get()
    #expect(read?.namesNoWindow == false)
    #expect(read?.missingOtherSpaceWindows == [150])
  }

  /// Both answers have to be "no value": a refused focused window leaves
  /// the main window's "no value" saying nothing on its own.
  @Test
  func noMainWindowWithARefusedFocusedWindowIsNotNamingNone() {
    let application = FakeApplication(windowCount: 1)
    application.listedIndices = []
    application.attributeResult = { index, name in
      index == nil && name == kAXFocusedWindowAttribute ? (.failure, nil) : nil
    }

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [150]).get()
    #expect(application.attributesRead.contains(kAXMainWindowAttribute))
    #expect(read?.namesNoWindow == false)
  }

  /// Not asked, or asked without an answer, says nothing either way.
  @Test
  func anApplicationNotAskedOrNotAnsweringIsNotSaidToNameNone() {
    let unasked = FakeApplication(windowCount: 1)
    let failing = FakeApplication(windowCount: 1)
    failing.listedIndices = []
    failing.attributeResult = { index, name in
      index == nil && name == kAXMainWindowAttribute ? (.cannotComplete, nil) : nil
    }

    #expect((try? unasked.read(includesOtherSpaces: true, otherSpaceWindows: [100]).get())?.namesNoWindow == false)
    #expect((try? failing.read(includesOtherSpaces: true, otherSpaceWindows: [150]).get())?.namesNoWindow == false)
  }

  /// A read already out of time asks nothing more, and says it was cut.
  @Test
  func aReadOutOfTimeAsksNothingMore() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = []
    application.mainWindowIndex = 1
    application.probeCost = ReadBudget.limit

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [101]).get()
    #expect(read?.otherSpacesCutShort == true)
    #expect(read?.missingOtherSpaceWindows == [101])
    #expect(!application.attributesRead.contains(kAXMainWindowAttribute))
  }

  /// A failed answer keeps what was read, like any failure on the way to
  /// other Spaces.
  @Test
  func aFailedMainWindowAnswerKeepsTheListedWindows() {
    let application = FakeApplication(windowCount: 2)
    application.listedIndices = [0]
    application.attributeResult = { index, name in
      index == nil && name == kAXMainWindowAttribute ? (.cannotComplete, nil) : nil
    }

    let read = try? application.read(includesOtherSpaces: true, otherSpaceWindows: [101]).get()
    #expect(read?.records.map(\.windowID) == [100])
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
