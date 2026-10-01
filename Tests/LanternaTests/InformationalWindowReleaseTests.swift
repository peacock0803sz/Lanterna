import AppKit
@testable import Lanterna
import Testing

/// Informational windows stay owned by their holder after the user closes them.
///
/// Regression test for issue #126: with `isReleasedWhenClosed` left at the
/// AppKit default, closing the window via the red button frees it while the
/// holder (`AppDelegate.settingsWindow`, `GuideWindows`) still points at it.
/// The next open then messages a dangling pointer (`EXC_BAD_ACCESS` in
/// `openSettings`, `objc_release` in `openGuide`/`openVersionLog`).
@MainActor
struct InformationalWindowReleaseTests {
  @Test
  func settingsWindowIsNotReleasedWhenClosed() {
    let window = SettingsWindow(
      values: SettingsValues.defaults,
      version: DisplayedVersion(full: "0.0.0"),
      permissionState: PermissionState(accessibilityGranted: false, inputMonitoringGranted: false),
      opener: { _ in false },
      onChange: { _ in }
    )
    #expect(window.isReleasedWhenClosed == false)
  }

  @Test
  func onboardingWindowIsNotReleasedWhenClosed() {
    let window = OnboardingWindow(missing: [], opener: { _ in false })
    #expect(window.isReleasedWhenClosed == false)
  }

  @Test
  func versionLogWindowIsNotReleasedWhenClosed() {
    let window = VersionLogWindow(state: LogWindowState(readEntries: { [] }))
    #expect(window.isReleasedWhenClosed == false)
  }

  /// The log window is built once and kept: reopening brings the same
  /// window forward with the same state behind it.
  @Test
  func reopeningTheLogWindowKeepsTheSameWindow() {
    let guides = GuideWindows(logState: LogWindowState(readEntries: { [] }))
    let first = guides.logWindow()
    first.close()
    #expect(guides.logWindow() === first)
  }

  @Test
  func theLogWindowOpensAtItsDefaultSizeAndTitle() {
    let window = VersionLogWindow(state: LogWindowState(readEntries: { [] }))
    #expect(window.title == "Lanterna Logs")
    #expect(window.contentRect(forFrameRect: window.frame).size == VersionLogWindow.defaultSize)
    #expect(window.styleMask.contains(.resizable))
  }
}
