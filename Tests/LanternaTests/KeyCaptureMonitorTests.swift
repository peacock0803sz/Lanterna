import AppKit
@testable import Lanterna
import Testing

/// Which presses a Keyboard tab capture takes, and when it lets go.
@MainActor
struct KeyCaptureMonitorTests {

  // MARK: Internal

  /// A press aimed at the armed window is handed over and swallowed.
  @Test
  func pressInArmedWindowIsTaken() throws {
    let window = makeWindow()
    defer { window.close() }
    let capture = KeyCaptureMonitor()
    var taken = [UInt16]()
    capture.arm(in: window) { taken.append($0.keyCode) }
    let press = try keyDown(in: window)
    #expect(press.window === window)
    #expect(capture.handle(press) == nil)
    #expect(taken == [press.keyCode])
    capture.disarm()
  }

  /// A press aimed at another window passes through untouched.
  @Test
  func pressInOtherWindowPassesThrough() throws {
    let window = makeWindow()
    let other = makeWindow()
    defer {
      window.close()
      other.close()
    }
    let capture = KeyCaptureMonitor()
    var taken = [UInt16]()
    capture.arm(in: window) { taken.append($0.keyCode) }
    let press = try keyDown(in: other)
    #expect(press.window === other)
    #expect(capture.handle(press) === press)
    #expect(taken.isEmpty)
    capture.disarm()
  }

  /// Closing the armed window disarms, so later presses pass through.
  @Test
  func closingArmedWindowDisarms() throws {
    let window = makeWindow()
    let capture = KeyCaptureMonitor()
    var taken = [UInt16]()
    capture.arm(in: window) { taken.append($0.keyCode) }
    #expect(capture.isArmed)
    let press = try keyDown(in: window)
    window.close()
    #expect(!capture.isArmed)
    #expect(capture.handle(press) === press)
    #expect(taken.isEmpty)
  }

  // MARK: Private

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    return window
  }

  private func keyDown(in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "k",
      charactersIgnoringModifiers: "k",
      isARepeat: false,
      keyCode: 40
    ))
  }

}
