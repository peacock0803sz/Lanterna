import AppKit
import SwiftUI

// MARK: - VersionLogWindow

/// The log window.
///
/// Independent from the onboarding window: it opens from the menu-bar entry on
/// any launch, whether or not anything is missing. It reads the store without
/// changing it, and it owns no keyboard monitoring of any kind.
@MainActor
final class VersionLogWindow: NSWindow {

  // MARK: Lifecycle

  /// Shows this launch so far: the version, the pinned summary, then the
  /// mirrored lines in order. A snapshot at opening time; reopening takes a
  /// fresh one.
  convenience init(
    version: DisplayedVersion,
    summary: String?,
    entries _: [DisplayedLogEntry],
    appearanceMode: AppearanceMode = .system
  ) {
    self.init(version: version, summary: summary, appearanceMode: appearanceMode)
  }

  convenience init(
    version: DisplayedVersion,
    summary: String?,
    appearanceMode: AppearanceMode = .system,
    state: LogWindowState
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
    contentView = NSHostingView(rootView: LogWindowView(
      version: version,
      summary: summary,
      state: state
    ))
    center()
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
