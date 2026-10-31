import AppKit

// MARK: - KeyCaptureActivity

/// Whether some settings row is waiting for a key press to bind.
///
/// Read outside the settings window: a Fast Search started by the press
/// being recorded would take the press the user meant to bind. One for the
/// process, because the monitors that report here live in SwiftUI state
/// that nothing outside the view can reach.
@MainActor
final class KeyCaptureActivity {

  static let shared = KeyCaptureActivity()

  private(set) var isCapturing = false

  /// Told on every change, with the new answer.
  var onChange: (@MainActor (Bool) -> Void)?

  func set(_ capturing: Bool) {
    guard capturing != isCapturing else { return }
    isCapturing = capturing
    onChange?(capturing)
  }

}

// MARK: - KeyCaptureMonitor

/// The key-down monitor behind a Keyboard tab capture, tied to one window.
///
/// The monitor is app-wide, so it takes only presses aimed at the window
/// that armed it and lets every other press through. Closing that window
/// disarms it: closing does not fire the content's `onDisappear`, so the
/// view alone would leave the monitor behind.
@MainActor
final class KeyCaptureMonitor {

  // MARK: Lifecycle

  init(activity: KeyCaptureActivity = .shared) {
    self.activity = activity
  }

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
    activity.set(true)
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
    activity.set(false)
  }

  /// Takes a press aimed at the armed window and swallows it; anything
  /// else, or any press while disarmed, passes through untouched.
  func handle(_ event: NSEvent) -> NSEvent? {
    guard let onKey, let host, event.window === host else { return event }
    onKey(event)
    return nil
  }

  // MARK: Private

  private let activity: KeyCaptureActivity
  private var monitor: Any?
  private var closeObserver: NSObjectProtocol?
  private weak var host: NSWindow?
  private var onKey: ((NSEvent) -> Void)?

}
