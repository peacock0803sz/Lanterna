import AppKit
@testable import Lanterna
import Testing

/// Which own windows become rows, and what those rows carry.
///
/// The live read-off from `NSApp` stays thin by design; these pin the
/// rules it applies: titled and visible only, never the panel, with
/// this process named and pictured on every row.
@MainActor
struct OwnWindowsTests {

  // MARK: Internal

  @Test
  func titledVisibleWindowIsListable() {
    #expect(OwnWindows.isListable(prospect()))
  }

  @Test(arguments: [
    (false, true, false),
    (true, false, false),
    (true, true, true),
  ])
  func panelUntitledAndHiddenWindowsStayOut(isTitled: Bool, isVisible: Bool, isPanel: Bool) {
    #expect(!OwnWindows.isListable(prospect(
      isTitled: isTitled,
      isVisible: isVisible,
      isPanel: isPanel
    )))
  }

  @Test
  func rowsCarryWindowNumberTitleAndOwner() {
    let rows = items([prospect(number: 7, title: "Lanterna Settings")])
    #expect(rows.count == 1)
    #expect(rows[0].id.windowID == 7)
    #expect(rows[0].windowTitle == "Lanterna Settings")
    #expect(rows[0].ownerProcessIdentifier == 123)
    #expect(rows[0].appName == "Lanterna")
    #expect(!rows[0].isMinimized)
  }

  @Test
  func minimizedProspectStaysListedAsMinimized() {
    let rows = items([prospect(isMiniaturized: true)])
    #expect(rows.count == 1)
    #expect(rows[0].isMinimized)
  }

  @Test
  func backgroundSpaceProspectBecomesOtherSpaceRow() {
    let rows = items([prospect(isOnActiveSpace: false)])
    #expect(rows.count == 1)
    #expect(rows[0].isOnOtherSpace)
  }

  @Test
  func displayNamePrefersBundleThenProcessThenPid() {
    #expect(OwnWindows.displayName(
      bundleName: "Lanterna",
      processName: "Lanterna",
      processIdentifier: 123
    ) == "Lanterna")
    #expect(OwnWindows.displayName(
      bundleName: nil,
      processName: "Lanterna",
      processIdentifier: 123
    ) == "Lanterna")
    #expect(OwnWindows.displayName(
      bundleName: nil,
      processName: "",
      processIdentifier: 123
    ) == "pid 123")
  }

  // MARK: Private

  private func prospect(
    number: Int = 7,
    title: String = "Lanterna Settings",
    isTitled: Bool = true,
    isVisible: Bool = true,
    isMiniaturized: Bool = false,
    isPanel: Bool = false,
    isOnActiveSpace: Bool = true
  ) -> OwnWindows.Prospect {
    OwnWindows.Prospect(
      number: number,
      title: title,
      isTitled: isTitled,
      isVisible: isVisible,
      isMiniaturized: isMiniaturized,
      isPanel: isPanel,
      isOnActiveSpace: isOnActiveSpace
    )
  }

  private func items(_ prospects: [OwnWindows.Prospect]) -> [WindowItem] {
    OwnWindows.items(
      prospects: prospects,
      owner: OwnWindows.Owner(
        processIdentifier: 123,
        appName: "Lanterna",
        bundleIdentifier: "net.p3ac0ck.Lanterna",
        isHidden: false,
        icon: AppIconResolver.placeholder
      )
    )
  }

}
