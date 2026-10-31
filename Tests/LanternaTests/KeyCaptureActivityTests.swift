import AppKit
@testable import Lanterna
import Testing

// MARK: - KeyCaptureActivityTests

/// Arming a capture says a press is being recorded, and disarming it, by
/// hand or by the window closing, says it no longer is.
@MainActor
struct KeyCaptureActivityTests {

  @Test
  func armingAndDisarmingAreReported() {
    let activity = KeyCaptureActivity()
    var reports = [Bool]()
    activity.onChange = { reports.append($0) }
    let monitor = KeyCaptureMonitor(activity: activity)

    monitor.arm(in: nil) { _ in }
    #expect(activity.isCapturing)
    monitor.arm(in: nil) { _ in }
    monitor.disarm()

    #expect(!activity.isCapturing)
    #expect(reports.last == false)
    #expect(reports.contains(true))
  }

  @Test
  func closingTheWindowEndsTheCapture() {
    let activity = KeyCaptureActivity()
    let monitor = KeyCaptureMonitor(activity: activity)
    let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false

    monitor.arm(in: window) { _ in }
    window.close()

    #expect(!activity.isCapturing)
  }

  @Test
  func repeatingTheSameAnswerSaysNothing() {
    let activity = KeyCaptureActivity()
    var reports = 0
    activity.onChange = { _ in reports += 1 }
    activity.set(false)
    activity.set(true)
    activity.set(true)
    #expect(reports == 1)
  }

}
