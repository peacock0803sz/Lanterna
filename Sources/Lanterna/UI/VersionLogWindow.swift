import AppKit
import SwiftUI

// MARK: - VersionLogWindow

/// The log window.
///
/// Independent from the onboarding window: it opens from the menu-bar entry on
/// any launch, whether or not anything is missing. It reads the store without
/// changing it, and it owns no keyboard monitoring of any kind. The version
/// and the launch summary live in the settings About area, not here.
@MainActor
final class VersionLogWindow: NSWindow {

  // MARK: Lifecycle

  /// Shows this launch so far: the version, the pinned summary, then the
  /// mirrored lines in order. A snapshot at opening time; reopening takes a
  /// fresh one. The version and the summary stay on the signature for
  /// existing callers; what the window shows comes from the shared state.
  convenience init(
    version _: DisplayedVersion,
    summary _: String?,
    entries _: [DisplayedLogEntry],
    appearanceMode: AppearanceMode = .system
  ) {
    self.init(appearanceMode: appearanceMode)
  }

  /// The shared contents behind the window. The version and the launch
  /// summary live in the settings About area; what the window shows
  /// comes from the state alone.
  convenience init(
    state: LogWindowState,
    appearanceMode: AppearanceMode = .system
  ) {
    self.init(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    // Held strongly by GuideWindows; releasing on close would dangle that reference.
    isReleasedWhenClosed = false
    title = "Lanterna Logs"
    appearance = appearanceMode.nsAppearance
    state.refresh()
    contentView = NSHostingView(rootView: LogWindowView(state: state))
    center()
  }

  convenience init(appearanceMode: AppearanceMode = .system) {
    self.init(state: LogWindowState(), appearanceMode: appearanceMode)
  }

  /// Kept for existing callers; the version and the summary no longer
  /// reach the window and stay unread here.
  convenience init(
    version _: DisplayedVersion,
    summary _: String?,
    appearanceMode: AppearanceMode = .system,
    state: LogWindowState
  ) {
    self.init(state: state, appearanceMode: appearanceMode)
  }

  convenience init(
    version: DisplayedVersion,
    summary: String?,
    appearanceMode: AppearanceMode = .system
  ) {
    self.init(version: version, summary: summary, appearanceMode: appearanceMode, state: LogWindowState())
  }

  // MARK: Internal

  /// Display-only clear point, kept across reopen until relaunch.
  static var clearMarkerMilliseconds: Int64?

}
