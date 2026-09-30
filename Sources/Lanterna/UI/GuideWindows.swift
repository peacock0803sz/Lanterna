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

  /// Shows this launch so far: the version, the pinned summary, then the
  /// mirrored lines in order. The store keeps growing underneath either way.
  func openVersionLog() {
    let window = VersionLogWindow(
      version: DisplayedVersion(full: AppVersion.full),
      summary: Diagnostics.launchSummary,
      entries: Diagnostics.recentEntries.map {
        DisplayedLogEntry(sequence: $0.sequence, capturedAt: $0.capturedAt, message: $0.message)
      },
      appearanceMode: appearanceMode
    )
    window.makeKeyAndOrderFront(nil)
    versionLogWindow = window
  }

  // MARK: Private

  /// Which appearance the guide windows draw in, settled at launch
  /// and re-settled whenever the settings change it.
  private var appearanceMode: AppearanceMode

  /// Held so each window stays up until the user closes it.
  private var guideWindow: OnboardingWindow?
  /// Held the same way, for the version and log window.
  private var versionLogWindow: VersionLogWindow?

}
