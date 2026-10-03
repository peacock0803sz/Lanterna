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
    focusedPosition: @escaping @Sendable (pid_t) -> CGPoint? = DisplayResolver.axFocusedPosition(of:),
    screens: @escaping @Sendable () -> [DisplayInfo] = DisplayResolver.currentScreens
  ) {
    self.cursor = cursor
    self.frontmostPID = frontmostPID
    self.focusedPosition = focusedPosition
    self.screens = screens
  }

  // MARK: Internal

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
    switch target {
    case .cursor:
      return DisplayTarget.resolve(target, cursor: cursor(), focusedWindow: nil, screens: screens)

    case .frontWindow:
      let point = frontmostPID().flatMap { focusedPosition($0) }
      return DisplayTarget.resolve(target, cursor: nil, focusedWindow: point, screens: screens)

    case .primary,
         .all:
      return DisplayTarget.resolve(target, cursor: nil, focusedWindow: nil, screens: screens)
    }
  }

  // MARK: Private

  private let cursor: @Sendable () -> CGPoint?
  private let frontmostPID: @Sendable () -> pid_t?
  private let focusedPosition: @Sendable (pid_t) -> CGPoint?
  private let screens: @Sendable () -> [DisplayInfo]

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

}
