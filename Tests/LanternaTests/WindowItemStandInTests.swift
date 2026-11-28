import AppKit
import Testing
@testable import Lanterna

/// An application row that stands for windows on hidden Spaces the read
/// could not reach, told apart from a row for an application with none.
@MainActor
struct WindowItemStandInTests {

  // MARK: Internal

  @Test
  func anApplicationRowWithNoWindowsElsewhereIsWindowless() {
    let row = applicationRow(windowsElsewhere: 0)

    #expect(row.isWindowless)
    #expect(!row.standsForWindowsElsewhere)
  }

  @Test
  func anApplicationRowWithWindowsElsewhereIsAStandIn() {
    let row = applicationRow(windowsElsewhere: 2)

    #expect(!row.isWindowless)
    #expect(row.standsForWindowsElsewhere)
  }

  @Test
  func aWindowRowIsNeither() {
    let row = WindowItem(
      id: .window(7),
      ownerProcessIdentifier: 1,
      appName: "Preview",
      bundleIdentifier: nil,
      windowTitle: "Report",
      kind: .standard,
      isMinimized: false,
      icon: NSImage()
    )

    #expect(!row.isWindowless)
    #expect(!row.standsForWindowsElsewhere)
  }

  @Test
  func theCaptionCountsTheWindowsElsewhere() {
    #expect(applicationRow(windowsElsewhere: 1).elsewhereCaption == "1 window on another desktop")
    #expect(applicationRow(windowsElsewhere: 2).elsewhereCaption == "2 windows on other desktops")
  }

  /// The optimistic look rebuilds rows; a stand-in must stay one.
  @Test
  func rebuildingARowKeepsItsWindowsElsewhere() {
    let row = applicationRow(windowsElsewhere: 3)

    #expect(row.settingMinimized(true).windowsElsewhere == 3)
    #expect(row.settingHidden(true).windowsElsewhere == 3)
    #expect(row.settingFullscreen(true).windowsElsewhere == 3)
  }

  // MARK: Private

  private func applicationRow(windowsElsewhere: Int) -> WindowItem {
    WindowItem(
      id: .application(1),
      ownerProcessIdentifier: 1,
      appName: "Preview",
      bundleIdentifier: nil,
      windowTitle: "",
      kind: .standard,
      isMinimized: false,
      isOnOtherSpace: windowsElsewhere > 0,
      windowsElsewhere: windowsElsewhere,
      icon: NSImage()
    )
  }

}
