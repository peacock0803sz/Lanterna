import AppKit

/// The key-down monitor behind a Keyboard tab capture, tied to one window.
///
/// The monitor is app-wide, so it takes only presses aimed at the window
/// that armed it and lets every other press through. Closing that window
/// disarms it: closing does not fire the content's `onDisappear`, so the
/// view alone would leave the monitor behind.
@MainActor
final class KeyCaptureMonitor {

  // MARK: Internal

  /// Whether a press is being waited for.
  var isArmed: Bool {
    monitor != nil
  }

  /// Waits for the next press aimed at `window`, handing it to `onKey`.
  /// Arming again replaces the previous wait.
  func arm(in window: NSWindow?, onKey: @escaping (NSEvent) -> Void) {
    disarm()
    host = window
    self.onKey = onKey
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handle(event) ?? event
    }
    // No queue: the block runs inside the post, on the main thread that
    // closes the window, so no press slips in before the disarm.
    closeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: window,
      queue: nil
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.disarm()
      }
    }
  }

  /// Stops waiting. A press already handed over stays handled.
  func disarm() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    if let closeObserver {
      NotificationCenter.default.removeObserver(closeObserver)
    }
    monitor = nil
    closeObserver = nil
    host = nil
    onKey = nil
  }

  /// Takes a press aimed at the armed window and swallows it; anything
  /// else, or any press while disarmed, passes through untouched.
  func handle(_ event: NSEvent) -> NSEvent? {
    guard let onKey, let host, event.window === host else { return event }
    onKey(event)
    return nil
  }

  // MARK: Private

  private var monitor: Any?
  private var closeObserver: NSObjectProtocol?
  private weak var host: NSWindow?
  private var onKey: ((NSEvent) -> Void)?

}
