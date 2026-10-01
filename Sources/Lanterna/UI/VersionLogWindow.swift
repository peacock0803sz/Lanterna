import AppKit
import Foundation
import SwiftUI

// MARK: - DisplayedVersion

/// The on-screen version, straight from the generated file.
struct DisplayedVersion: Equatable {
  /// The full describe string, exactly as `Version.swift` holds it.
  let full: String
}

// MARK: - VersionLogWindow

/// The Lanterna Logs window.
///
/// Independent from the onboarding window: it opens from the menu-bar entry on
/// any launch, whether or not anything is missing. It reads the diagnostics
/// without changing them, and it owns no keyboard monitoring of any kind. The
/// contents come from a state the caller keeps, so closing and reopening the
/// window finds the same filters and rows.
@MainActor
final class VersionLogWindow: NSWindow {

  // MARK: Lifecycle

  convenience init(state: LogWindowState, appearanceMode: AppearanceMode = .system) {
    self.init(
      contentRect: NSRect(origin: .zero, size: Self.defaultSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    // Held strongly by GuideWindows; releasing on close would dangle that reference (#126).
    isReleasedWhenClosed = false
    title = "Lanterna Logs"
    // The traffic lights share the toolbar's row rather than sitting in a
    // title bar of their own.
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    contentMinSize = Self.minimumSize
    appearance = appearanceMode.nsAppearance
    contentView = NSHostingView(rootView: LogWindowView(state: state))
    setContentSize(Self.defaultSize)
    center()
    // Polling follows what the reader can see: a closed, minimised or
    // fully covered window takes nothing in until it shows again.
    occlusionObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeOcclusionStateNotification,
      object: self,
      queue: .main
    ) { [weak self, weak state] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        state?.setVisible(self.occlusionState.contains(.visible))
      }
    }
  }

  // MARK: Internal

  static let defaultSize = NSSize(width: 900, height: 600)
  static let minimumSize = NSSize(width: 640, height: 360)

  // MARK: Private

  private var occlusionObserver: (any NSObjectProtocol)?

}
