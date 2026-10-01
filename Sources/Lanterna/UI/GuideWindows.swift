import AppKit

/// Owns the two informational windows.
///
/// Split out of the application delegate when it reached the file-length
/// limit: these windows share nothing with the hotkey paths, so they stand
/// alone. Both are snapshots at opening time; reopening takes a fresh one.
@MainActor
final class GuideWindows {

  // MARK: Lifecycle

  init(appearanceMode: AppearanceMode = .system) {
    self.appearanceMode = appearanceMode
  }

  // MARK: Internal

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

  /// Shows live and spilled rows in one resizable shell. The window and
  /// its query are held for the whole launch: reopening brings the same
  /// window forward with the last query kept and contents refreshed.
  /// A fresh launch builds a fresh holder, so the first open starts
  /// from the default query and time range.
  func openVersionLog() {
    if versionLogWindow == nil {
      versionLogWindow = VersionLogWindow(
        state: logWindowState,
        appearanceMode: appearanceMode
      )
    } else {
      logWindowState.refresh()
    }
    // Like the guide and settings windows: ordering front alone leaves
    // this behind the frontmost app under the accessory policy.
    NSApp.activate(ignoringOtherApps: true)
    versionLogWindow?.makeKeyAndOrderFront(nil)
  }

  // MARK: Private

  /// Which appearance the guide windows draw in, settled at launch
  /// and re-settled whenever the settings change it.
  private var appearanceMode: AppearanceMode

  /// Held so each window stays up until the user closes it.
  private var guideWindow: OnboardingWindow?
  /// Held the same way, for the version and log window.
  private var versionLogWindow: VersionLogWindow?
  /// The log query and view options for the whole launch. Held beside
  /// the window so reopening keeps what was asked before.
  private var logWindowState = LogWindowState()

}
