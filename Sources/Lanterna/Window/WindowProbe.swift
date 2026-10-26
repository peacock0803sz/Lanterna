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
/// already have. A full pass costs tens to a couple of hundred milliseconds
/// on an ordinary application, which is why every call carries a deadline.
enum WindowProbe {

  // MARK: Internal

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

  /// The windows found by id, ending the pass at `deadline` or, when `target`
  /// is given, once a window with that id has been found.
  ///
  /// A nonexistent id answers an error at once. That is the common case and
  /// says nothing about the application, so it is skipped silently. Untitled
  /// helper windows the accessibility server never exposes are not found.
  static func windows(
    of pid: pid_t,
    stoppingAt target: CGWindowID?,
    until deadline: ContinuousClock.Instant
  ) -> [ProbedWindow] {
    var found = [ProbedWindow]()
    for id in elementIDs {
      if ContinuousClock.now >= deadline {
        break
      }
      guard
        let element = _AXUIElementCreateWithRemoteToken(token(pid: pid, elementID: id) as CFData),
        AXUIElementSetMessagingTimeout(element, probeTimeout) == .success,
        let windowID = windowID(ifWindow: element)
      else { continue }
      found.append(ProbedWindow(element: element, windowID: windowID))
      if windowID == target {
        break
      }
    }
    return found
  }

  // MARK: Private

  /// Measured on one machine (macOS 26, about 20 regular applications): every
  /// titled window of another Space answered within this range, and widening
  /// it to 20000 found nothing more. Beyond that machine it is a guess; an
  /// application that numbers its elements higher loses those windows.
  private static let elementIDs: Range<UInt64> = 0..<1000
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
