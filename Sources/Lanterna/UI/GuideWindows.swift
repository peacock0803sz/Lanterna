import AppKit

/// Owns the two informational windows.
///
/// Split out of the application delegate when it reached the file-length
/// limit: these windows share nothing with the hotkey paths, so they stand
/// alone. The onboarding window is a snapshot at opening time; the log
/// window is one window for the whole run, over a state that outlives it.
@MainActor
final class GuideWindows {

  // MARK: Lifecycle

  init(appearanceMode: AppearanceMode = .system, logState: LogWindowState = LogWindowState()) {
    self.appearanceMode = appearanceMode
    self.logState = logState
  }

  // MARK: Internal

  /// What the log window shows. Kept for the whole run, so closing the
  /// window keeps its filters and rows.
  let logState: LogWindowState

  /// Shows the onboarding window for the launch-time answers.
  ///
  /// Reopening shows the same answers: the state is read once per launch,
  /// so a grant given while the app runs changes nothing until the next
  /// launch, and the guide says exactly that.
  func openGuide(state: PermissionState) {
    // Close the held window first so reopening leaves exactly one.
    guideWindow?.close()
    let window = OnboardingWindow(
      missing: MissingPermission.list(for: state),
      opener: SystemSettings.open,
      appearanceMode: appearanceMode
    )
    // The accessory policy never brings the app forward on its own. At
    // login or a Finder launch another app is frontmost, and ordering
    // front alone can leave this guide behind it.
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    guideWindow = window
  }

  /// Follows a settings change: later windows open in the new look,
  /// and any window still up is restyled in place.
  func update(appearanceMode: AppearanceMode) {
    self.appearanceMode = appearanceMode
    guideWindow?.appearance = appearanceMode.nsAppearance
    versionLogWindow?.appearance = appearanceMode.nsAppearance
  }

  /// Brings the log window forward, making it on first use. An open
  /// window is only brought forward: building it again would throw away
  /// where the reader was.
  func openVersionLog() {
    let window = logWindow()
    // Like the guide and settings windows: ordering front alone leaves
    // this behind the frontmost app under the accessory policy.
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  /// The one log window of this run, built on first use.
  func logWindow() -> VersionLogWindow {
    if let versionLogWindow {
      return versionLogWindow
    }
    let window = VersionLogWindow(state: logState, appearanceMode: appearanceMode)
    versionLogWindow = window
    return window
  }

  // MARK: Private

  /// Which appearance the guide windows draw in, settled at launch
  /// and re-settled whenever the settings change it.
  private var appearanceMode: AppearanceMode

  /// Held so each window stays up until the user closes it.
  private var guideWindow: OnboardingWindow?
  /// Held the same way, for the log window. Kept after closing, so the
  /// next open shows the same window.
  private var versionLogWindow: VersionLogWindow?

}
