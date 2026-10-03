import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - DisplayResolver

/// Reads where the panel opens from live sources, then answers with
/// plain values.
///
/// The reads are injected so tests answer from fixed points while the
/// running application reads the cursor, the frontmost application and
/// its focused window. The focused-window read follows the same round
/// trip as the activation record, with the same messaging timeout: a
/// wedged application costs at most that long, once, and the panel
/// falls back to the menu-bar display.
struct DisplayResolver: Sendable {

  // MARK: Lifecycle

  init(
    cursor: @escaping @Sendable () -> CGPoint? = { NSEvent.mouseLocation },
    frontmostPID: @escaping @Sendable () -> pid_t? = {
      NSWorkspace.shared.frontmostApplication?.processIdentifier
    },
    ownPID: @escaping @Sendable () -> pid_t = { ProcessInfo.processInfo.processIdentifier },
    focusedPosition: @escaping @Sendable (pid_t) -> CGPoint? = DisplayResolver.axFocusedPosition(of:),
    screens: @escaping @Sendable () -> [DisplayInfo] = DisplayResolver.currentScreens
  ) {
    self.cursor = cursor
    self.frontmostPID = frontmostPID
    self.ownPID = ownPID
    self.focusedPosition = focusedPosition
    self.screens = screens
  }

  // MARK: Internal

  /// The connected displays, so callers map a resolved index back to
  /// the same screens the call resolved over.
  let screens: @Sendable () -> [DisplayInfo]

  /// The connected displays as the resolution sees them, with the
  /// menu-bar display first.
  static func currentScreens() -> [DisplayInfo] {
    let all = NSScreen.screens
    return all.map { screen in
      DisplayInfo(frame: screen.frame, isPrimary: screen == all.first)
    }
  }

  /// Picks the display for one appearance over the current screens.
  func resolve(_ target: DisplayTarget) -> ResolvedDisplay {
    resolve(target, over: screens())
  }

  /// Picks the display over explicit screens, so rearranged displays
  /// read as a value test with no window server involved.
  func resolve(_ target: DisplayTarget, over screens: [DisplayInfo]) -> ResolvedDisplay {
    resolveWithFallback(target, over: screens).display
  }

  /// Resolves with whether the menu-bar display was a fallback rather
  /// than the answer, so the caller can say so on the diagnostics line.
  func resolveWithFallback(
    _ target: DisplayTarget,
    over screens: [DisplayInfo]
  ) -> (display: ResolvedDisplay, fellBack: Bool) {
    switch target {
    case .cursor:
      let point = cursor()
      return (
        DisplayTarget.resolve(target, cursor: point, focusedWindow: nil, screens: screens),
        unplaced(point, in: screens)
      )

    case .frontWindow:
      // The panel itself never counts as the front window, so this
      // read treats the running application as no placed point.
      let own = ownPID()
      let point = frontmostPID().flatMap { $0 == own ? nil : focusedPosition($0) }
      return (
        DisplayTarget.resolve(target, cursor: nil, focusedWindow: point, screens: screens),
        unplaced(point, in: screens)
      )

    case .primary,
         .all:
      return (
        DisplayTarget.resolve(target, cursor: nil, focusedWindow: nil, screens: screens),
        false
      )
    }
  }

  // MARK: Private

  private let cursor: @Sendable () -> CGPoint?
  private let frontmostPID: @Sendable () -> pid_t?
  private let ownPID: @Sendable () -> pid_t
  private let focusedPosition: @Sendable (pid_t) -> CGPoint?

  /// The focused window's position over the accessibility API, or
  /// nothing when the read fails. Each call makes and drops its own
  /// elements, so nothing is shared between calls.
  private static func axFocusedPosition(of processIdentifier: pid_t) -> CGPoint? {
    let application = AXUIElementCreateApplication(processIdentifier)
    guard AXUIElementSetMessagingTimeout(application, 1.0) == .success else {
      return nil
    }
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        application,
        kAXFocusedWindowAttribute as CFString,
        &focused
      ) == .success,
      let focused,
      CFGetTypeID(focused) == AXUIElementGetTypeID()
    else {
      return nil
    }
    let element = unsafeDowncast(focused, to: AXUIElement.self)
    guard AXUIElementSetMessagingTimeout(element, 1.0) == .success else {
      return nil
    }
    var position: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        kAXPositionAttribute as CFString,
        &position
      ) == .success,
      let position,
      CFGetTypeID(position) == AXValueGetTypeID()
    else {
      return nil
    }
    let value = unsafeDowncast(position, to: AXValue.self)
    guard AXValueGetType(value) == .cgPoint else {
      return nil
    }
    var point = CGPoint.zero
    guard AXValueGetValue(value, .cgPoint, &point) else {
      return nil
    }
    return point
  }

  /// True when the point is missing or held by no screen.
  private func unplaced(_ point: CGPoint?, in screens: [DisplayInfo]) -> Bool {
    guard let point else {
      return true
    }
    return !screens.contains(where: { $0.frame.contains(point) })
  }

}
