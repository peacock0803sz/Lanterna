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
    focusedFrame: @escaping @Sendable (pid_t) -> CGRect? = DisplayResolver.axFocusedFrame(of:),
    screens: @escaping @Sendable () -> [DisplayInfo] = DisplayResolver.currentScreens
  ) {
    self.cursor = cursor
    self.frontmostPID = frontmostPID
    self.ownPID = ownPID
    self.focusedFrame = focusedFrame
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

  /// The centre of a window frame read over the accessibility API, in
  /// the Cocoa base coordinate space the screen frames use.
  ///
  /// Accessibility frames put the origin at the top-left corner of the
  /// menu-bar display with y growing downwards, while Cocoa puts it at
  /// that display's bottom-left corner with y growing upwards. The flip
  /// therefore pivots on the menu-bar display's top edge. Nothing comes
  /// back when no screen is known to pivot on.
  static func cocoaCentre(
    ofAccessibilityFrame frame: CGRect,
    over screens: [DisplayInfo]
  ) -> CGPoint? {
    guard let primary = screens.first(where: \.isPrimary) ?? screens.first else {
      return nil
    }
    return CGPoint(x: frame.midX, y: primary.frame.maxY - frame.midY)
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
      let frame = frontmostPID().flatMap { $0 == own ? nil : focusedFrame($0) }
      let point = frame.flatMap { Self.cocoaCentre(ofAccessibilityFrame: $0, over: screens) }
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
  private let focusedFrame: @Sendable (pid_t) -> CGRect?

  /// The focused window's frame over the accessibility API, in that
  /// API's own top-left coordinate space, or nothing when the read
  /// fails. Each call makes and drops its own elements, so nothing is
  /// shared between calls. The read asks the application for its
  /// focused window and then asks that window for its position and its
  /// size; every one of those messages carries a 1.0s messaging timeout
  /// and can wait it out, after which the caller falls back to the
  /// menu-bar display with a diagnostics line.
  private static func axFocusedFrame(of processIdentifier: pid_t) -> CGRect? {
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
    var origin = CGPoint.zero
    guard axValue(of: element, attribute: kAXPositionAttribute, type: .cgPoint, into: &origin) else {
      return nil
    }
    var size = CGSize.zero
    guard axValue(of: element, attribute: kAXSizeAttribute, type: .cgSize, into: &size) else {
      return nil
    }
    return CGRect(origin: origin, size: size)
  }

  /// Copies one accessibility attribute holding a geometry value into
  /// `result`, answering false when the read fails or the value has
  /// another type.
  private static func axValue(
    of element: AXUIElement,
    attribute: String,
    type: AXValueType,
    into result: inout some BitwiseCopyable
  ) -> Bool {
    var raw: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
      let raw,
      CFGetTypeID(raw) == AXValueGetTypeID()
    else {
      return false
    }
    let value = unsafeDowncast(raw, to: AXValue.self)
    return AXValueGetType(value) == type && AXValueGetValue(value, type, &result)
  }

  /// True when the point is missing or held by no screen.
  private func unplaced(_ point: CGPoint?, in screens: [DisplayInfo]) -> Bool {
    guard let point else {
      return true
    }
    return !screens.contains(where: { $0.frame.contains(point) })
  }

}
