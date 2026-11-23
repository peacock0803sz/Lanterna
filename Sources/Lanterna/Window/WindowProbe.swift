import ApplicationServices
import PrivateAPIs

// MARK: - ProbedWindow

/// A window the probe found, with the window-server id it already read to
/// tell a window from any other element.
struct ProbedWindow {
  let element: AXUIElement
  let windowID: CGWindowID
}

// MARK: - WindowProbe

/// Finds the windows of one application by asking for its element ids one by
/// one, instead of reading its window list.
///
/// The list leaves out the windows on a Space no display is showing, and
/// nothing public reaches them, so this is the only source of their elements:
/// listing them and switching to them agree on what exists. It returns every
/// window it finds, those the list holds too; callers subtract what they
/// already have and name the windows they want, so the pass ends once those
/// have turned up. A full pass costs tens to a couple of hundred milliseconds
/// on an ordinary application, which is why every call carries a deadline.
enum WindowProbe {

  // MARK: Internal

  /// The ids looked through for every application with a window the list
  /// lacks. Where measured, the windows of most applications answered near
  /// the bottom of it, but a Chromium-based browser numbered its window past
  /// the end.
  static let elementIDs: Range<UInt64> = 0..<1000

  /// The ids looked through after `elementIDs`, only for an application left
  /// without a single window row. Bounded rather than left to the deadline,
  /// so a search that finds nothing ends early and reads as windows not
  /// found instead of a read cut short; sized to fit well inside a read's
  /// budget where measured. A window numbered past it is not found, and the
  /// summary line names its application among the windows not found.
  static let widenedElementIDs: Range<UInt64> = elementIDs.upperBound..<20000

  /// The 20-byte token naming one element of one process: the process id
  /// (`Int32`), `Int32` 0, `Int32` 0x636F636F, then the element id (`UInt64`),
  /// all in native byte order.
  static func token(pid: pid_t, elementID: UInt64) -> Data {
    var token = Data(capacity: 20)
    for word: Int32 in [pid, 0, 0x636F_636F] {
      withUnsafeBytes(of: word) { token.append(contentsOf: $0) }
    }
    withUnsafeBytes(of: elementID) { token.append(contentsOf: $0) }
    return token
  }

  /// The windows found among `ids`, ending the pass at `deadline` or once
  /// every window in `targets` has been found. An empty `targets` looks
  /// through the whole range.
  ///
  /// A nonexistent id answers an error at once. That is the common case and
  /// says nothing about the application, so it is skipped silently. Untitled
  /// helper windows the accessibility server never exposes are not found.
  static func windows(
    of pid: pid_t,
    ids: Range<UInt64>,
    stoppingAfter targets: Set<CGWindowID>,
    until deadline: ContinuousClock.Instant
  ) -> [ProbedWindow] {
    search(ids: ids, stoppingAfter: targets, until: deadline, now: { .now }) { id in
      guard
        let element = _AXUIElementCreateWithRemoteToken(token(pid: pid, elementID: id) as CFData),
        AXUIElementSetMessagingTimeout(element, probeTimeout) == .success,
        let windowID = windowID(ifWindow: element)
      else { return nil }
      return ProbedWindow(element: element, windowID: windowID)
    }
  }

  /// The loop behind `windows(of:ids:stoppingAfter:until:)`, apart from the
  /// accessibility calls so when it stops can be tested. `look` answers
  /// one id: the window there, or nil.
  static func search(
    ids: Range<UInt64>,
    stoppingAfter targets: Set<CGWindowID>,
    until deadline: ContinuousClock.Instant,
    now: () -> ContinuousClock.Instant,
    look: (UInt64) -> ProbedWindow?
  ) -> [ProbedWindow] {
    var found = [ProbedWindow]()
    var remaining = targets
    for id in ids {
      if now() >= deadline {
        break
      }
      guard let window = look(id) else { continue }
      found.append(window)
      if remaining.remove(window.windowID) != nil, remaining.isEmpty {
        break
      }
    }
    return found
  }

  // MARK: Private

  private static let probeTimeout: Float = 0.1

  private static func windowID(ifWindow element: AXUIElement) -> CGWindowID? {
    var role: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
      role as? String == kAXWindowRole
    else { return nil }
    var windowID: CGWindowID = 0
    guard _AXUIElementGetWindow(element, &windowID) == .success, windowID != 0 else { return nil }
    return windowID
  }

}
